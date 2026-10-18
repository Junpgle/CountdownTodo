import 'dart:async';
import 'dart:convert';

import '../features/finance/models/finance_models.dart';
import 'ai_action_parser.dart';
import 'ai_chat_service.dart';
import 'ai_native_tool_call_parser.dart';
import 'ai_native_tool_definition_builder.dart';
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
  static final RegExp _legacyTextToolBlock = RegExp(
    r'<tool_call\b[^>]*>([\s\S]*?)</tool_call\s*>',
    caseSensitive: false,
  );
  static final RegExp _legacyTextToolOpen = RegExp(
    r'<tool_call\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _legacyTextToolClose = RegExp(
    r'</tool_call\s*>',
    caseSensitive: false,
  );

  static String _visibleTextBeforeLegacyToolCalls(String content) {
    final lowerContent = content.toLowerCase();
    var cursor = 0;
    final visible = StringBuffer();
    while (cursor < content.length) {
      final openMatches = _legacyTextToolOpen.allMatches(content, cursor);
      final openMatch = openMatches.isEmpty ? null : openMatches.first;
      final closeMatches = _legacyTextToolClose.allMatches(content, cursor);
      final closeBeforeOpen = closeMatches.isEmpty
          ? null
          : closeMatches.first;
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

  static ({
    String content,
    List<AiChatFunctionCall> calls,
    bool hadToolMarkup,
  }) _parseLegacyTextToolCalls(
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
      if (function == null) continue;

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
        if (arguments['domain'] != null &&
            arguments['domain'] != aliasedDomain) {
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
    );
  }

  static dynamic _decodeLegacyJsonValue(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  static ({bool valid, dynamic value}) _parseLegacyTextParameterValue(
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
        'boolean' => rawValue.toLowerCase() == 'true'
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
    String previousUserMessage = '',
    String previousAssistantMessage = '',
    Set<String>? knownTodoIds,
    Set<String>? knownHabitIds,
    Set<String>? knownFinanceTransactionIds,
    Map<String, Set<String>>? knownFinanceCatalogIdsByKind,
    Map<String, Set<String>>? knownReferenceIdsByDomain,
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
    var callCount = 0;
    var proposalsProduced = false;
    var planningRepairAttempted = false;
    var planningScheduleRepairAttempted = false;
    var actionProposalRepairAttempted = false;
    var missingWriteProposalRepairAttempted = false;
    var actionRepairQueriesUsed = false;
    var referenceProposalRetryUsed = false;
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
    final queriedReferenceDomains = <String>{};
    final pendingReferenceDomains = <String>{};
    final referenceReadyDomains = <String>{};
    final requiredWriteProposalNames = tools
        .map((tool) => (tool['function'] as Map)['name'] as String)
        .where(_writeProposalToolNames.contains)
        .toSet();
    final completedWriteProposalNames = <String>{};
    var validatedFinanceTransactionIds = knownFinanceTransactionIds
        ?.map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    Map<String, Set<String>>? validatedFinanceCatalogIdsByKind =
        knownFinanceCatalogIdsByKind?.map(
          (kind, ids) => MapEntry(
            kind,
            ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet(),
          ),
        );
    var resultChars = 0;
    bool cancelled() => cancelToken?.isCompleted == true;
    String missingWriteProposalFailure(Set<String> missing) {
      if (completedWriteProposalNames.isEmpty) {
        return '模型未能生成有效写入提案，应用没有创建确认卡或写入数据。请补充信息后重试。';
      }
      final labels = missing
          .map((name) => switch (name) {
                'propose_cdt_actions' => '待办/日程/习惯操作',
                'propose_finance_drafts' => '记账草案',
                'propose_finance_actions' => '账单修改草案',
                _ => name,
              })
          .join('、');
      return '已生成部分待确认操作卡，但模型未能补齐：$labels。现有卡片尚未写入，请核对后再补充缺少的操作。';
    }

    for (var round = 0; round <= maxQueryRounds + 1; round++) {
      if (cancelled()) return;
      final finalRound =
          round >= maxQueryRounds ||
          callCount >= maxCalls ||
          resultChars > AiToolResultContext.maxTurnChars - 400;
      final unsubmittedWriteProposalNames = requiredWriteProposalNames.difference(
        completedWriteProposalNames,
      );
      final roundTools = tools.where((tool) {
        final name = (tool['function'] as Map)['name'] as String;
        final isQuery = AiQueryToolService.toolNames.contains(name);
        final isUnsubmittedWriteProposal =
            unsubmittedWriteProposalNames.contains(name);
        return (!finalRound || !isQuery) &&
            (!proposalsProduced || isQuery || isUnsubmittedWriteProposal) &&
            (!planningRepairAttempted ||
                isUnsubmittedWriteProposal) &&
            (!planningScheduleRepairAttempted ||
                isUnsubmittedWriteProposal) &&
            // Action recovery may query once to resolve a real local ID; after
            // that, keep only proposals unless a mixed call still has reads
            // left to finish.
            (!actionProposalRepairAttempted ||
                isUnsubmittedWriteProposal ||
                (isQuery && (!actionRepairQueriesUsed || proposalsProduced)));
      }).toList();
      final roundAllowedToolNames = {
        for (final tool in roundTools)
          (tool['function'] as Map)['name'] as String,
      };
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
      var streamedVisibleContent = '';
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
        final visibleContent = hasPlanningTool || hasWriteProposalTool
            ? ''
            : _visibleTextBeforeLegacyToolCalls(content);
        final visibleDelta = visibleContent.startsWith(streamedVisibleContent)
            ? visibleContent.substring(streamedVisibleContent.length)
            : '';
        streamedVisibleContent = visibleContent;
        yield AiChatStreamChunk(
          // Proposal prose stays buffered until we know whether an actual
          // call arrived. Never flash a false "created/saved" claim.
          content: visibleDelta,
          reasoningContent: chunk.reasoningContent,
          // Emit calls only after the complete proposal passes app-side
          // validation. Malformed writes must not reach the action parser.
          finishReason: chunk.finishReason,
          usage: chunk.usage,
          usageSummary: chunk.usageSummary,
        );
      }
      yield AiChatStreamChunk(
        rawModelReply: AiNativeToolCallParser.formatRawReply(content, calls),
      );
      if (cancelled()) return;
      final legacyCalls = _parseLegacyTextToolCalls(content, roundTools, round);
      content = legacyCalls.content;
      for (final call in legacyCalls.calls) {
        final duplicate = calls.any(
          (existing) =>
              existing.name == call.name &&
              existing.arguments.trim() == call.arguments.trim(),
        );
        if (!duplicate) calls.add(call);
      }
      final unsupportedLegacyToolMarkup =
          legacyCalls.hadToolMarkup &&
          legacyCalls.calls.isEmpty &&
          calls.isEmpty;
      if (unsupportedLegacyToolMarkup) {
        if (hasPlanningTool || hasWriteProposalTool) {
          if (content.trim().isEmpty) {
            content = '上一轮返回了当前未开放的文本工具调用。';
          }
        } else {
          content = [
            content.trim(),
            '模型返回了无法识别的查询调用格式，未读取数据。请重试。',
          ].where((part) => part.isNotEmpty).join('\n\n');
        }
      }
      final proposalValidationIssues = <String, String>{};
      final readCallsInRound = calls
          .where(
            (call) =>
                roundAllowedToolNames.contains(call.name) &&
                AiQueryToolService.toolNames.contains(call.name),
          )
          .toList(growable: false);
      var deferredReferenceProposal = false;
      var createdTodoCount = 0;
      var createdTodoRemarkCount = 0;
      var createdFinanceDraftCount = 0;
      for (final call in calls) {
        if (!_writeProposalToolNames.contains(call.name) ||
            !roundAllowedToolNames.contains(call.name)) {
          continue;
        }
        final matchingReadCallIds = _matchingQueryCallIdsForProposal(
          call,
          readCallsInRound,
        );
        final requiredReferenceDomains = _proposalReferenceDomains(call);
        final incompletePriorQueryDomains = requiredReferenceDomains
            .intersection(queriedReferenceDomains)
            .difference(referenceReadyDomains);
        final financeIdsForValidation =
            matchingReadCallIds.isNotEmpty ||
                incompletePriorQueryDomains.contains('finance_transactions')
            ? null
            : validatedFinanceTransactionIds;
        final financeCatalogIdsForValidation =
            matchingReadCallIds.isNotEmpty ||
                incompletePriorQueryDomains.contains('finance_catalog')
            ? null
            : validatedFinanceCatalogIdsByKind;
        var issue = _writeProposalValidationIssue(
          call,
          roundTools,
          requestText: planningRequestText,
          knownTodoIds: knownTodoIds,
          knownHabitIds: knownHabitIds,
          knownFinanceTransactionIds: financeIdsForValidation,
          knownFinanceCatalogIdsByKind: financeCatalogIdsForValidation,
          knownReferenceIdsByDomain: knownReferenceIdsByDomain,
        );
        if (matchingReadCallIds.isNotEmpty ||
            incompletePriorQueryDomains.isNotEmpty) {
          deferredReferenceProposal = true;
          pendingReferenceDomains.addAll(incompletePriorQueryDomains);
          for (final readCall in readCallsInRound) {
            if (matchingReadCallIds.contains(readCall.id)) {
              pendingReferenceDomains.addAll(
                _queryReferenceDomains(readCall),
              );
            }
          }
          final dependencyIssue =
              '本轮同时发起了只读查询和依赖现有对象的写入提案。查询结果尚未返回，'
              'App没有生成此提案的确认卡；请先使用查询结果中的真实ID，再单独提交写入提案。';
          issue = issue == null ? dependencyIssue : '$issue；$dependencyIssue';
        }
        final validationIssue = issue;
        if (validationIssue != null) {
          proposalValidationIssues.putIfAbsent(
            call.id,
            () => validationIssue,
          );
        } else if (call.name == 'propose_cdt_actions') {
          createdTodoCount += _createdTodoCount(call.arguments);
          createdTodoRemarkCount += _createdTodoRemarkCount(call.arguments);
        } else if (call.name == 'propose_finance_drafts') {
          createdFinanceDraftCount += _createdFinanceDraftCount(
            call.arguments,
          );
        }
      }
      final cdtProposalCalls = calls
          .where(
            (call) =>
                call.name == 'propose_cdt_actions' &&
                roundAllowedToolNames.contains(call.name),
          )
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
      final financeDraftCalls = calls
          .where(
            (call) =>
                call.name == 'propose_finance_drafts' &&
                roundAllowedToolNames.contains(call.name),
          )
          .toList(growable: false);
      final requestedFinanceDraftCount =
          AiTodoContextBuilder.explicitFinanceDraftCount(planningRequestText);
      if (requestedFinanceDraftCount != null &&
          financeDraftCalls.isNotEmpty &&
          createdFinanceDraftCount < requestedFinanceDraftCount) {
        final issue =
            '用户明确要求 $requestedFinanceDraftCount 笔新增账单，当前提案只有 $createdFinanceDraftCount 笔';
        for (final call in financeDraftCalls) {
          proposalValidationIssues.putIfAbsent(call.id, () => issue);
        }
      }
      final requiredCdtActionNames =
          AiTodoContextBuilder.requiredExplicitCdtActionNames(
            planningRequestText,
            previousUserMessage: previousUserMessage,
            previousAssistantMessage: previousAssistantMessage,
          ).intersection(
            AiNativeToolDefinitionBuilder.allowedCdtActionNames(roundTools),
          );
      if (cdtProposalCalls.isNotEmpty && requiredCdtActionNames.isNotEmpty) {
        final proposedCdtActionNames = <String>{};
        for (final call in cdtProposalCalls) {
          if (proposalValidationIssues.containsKey(call.id)) continue;
          proposedCdtActionNames.addAll(_cdtActionNames(call.arguments));
          if (_hasNewTodoInPlan(call.arguments)) {
            proposedCdtActionNames.add('create_todo');
          }
        }
        final missingCdtActionNames =
            requiredCdtActionNames.difference(proposedCdtActionNames);
        if (missingCdtActionNames.isNotEmpty) {
          final issue =
              '用户明确要求的 CDT 操作未全部包含：'
              '${missingCdtActionNames.map(_cdtActionLabel).join('、')}；'
              '当前提案只有 ${proposedCdtActionNames.map(_cdtActionLabel).join('、')}';
          for (final call in cdtProposalCalls) {
            proposalValidationIssues.update(
              call.id,
              (existing) => '$existing；$issue',
              ifAbsent: () => issue,
            );
          }
        }
      }
      final financeActionCalls = calls
          .where(
            (call) =>
                call.name == 'propose_finance_actions' &&
                roundAllowedToolNames.contains(call.name),
          )
          .toList(growable: false);
      final requiredFinanceActionNames =
          AiNativeToolDefinitionBuilder.allowedFinanceActionNames(roundTools);
      if (financeActionCalls.isNotEmpty &&
          requiredFinanceActionNames.isNotEmpty) {
        final proposedFinanceActionNames = <String>{};
        for (final call in financeActionCalls) {
          proposedFinanceActionNames.addAll(
            _financeActionNames(call.arguments),
          );
        }
        final missingFinanceActionNames = requiredFinanceActionNames.difference(
          proposedFinanceActionNames,
        );
        if (missingFinanceActionNames.isNotEmpty) {
          final issue =
              '用户明确要求的账单操作未全部包含：'
              '${missingFinanceActionNames.map(_financeActionLabel).join('、')}；'
              '当前提案只有 '
              '${proposedFinanceActionNames.map(_financeActionLabel).join('、')}';
          for (final call in financeActionCalls) {
            proposalValidationIssues.update(
              call.id,
              (existing) => '$existing；$issue',
              ifAbsent: () => issue,
            );
          }
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
      final validProposalNamesFromCalls = calls
          .where(
            (call) =>
                _writeProposalToolNames.contains(call.name) &&
                roundAllowedToolNames.contains(call.name) &&
                !proposalValidationIssues.containsKey(call.id),
          )
          .map((call) => call.name)
          .toSet();
      final missingWriteProposalNamesAfterRound = requiredWriteProposalNames
          .where(
            (name) =>
                !completedWriteProposalNames.contains(name) &&
                !validProposalNamesFromCalls.contains(name),
          )
          .toSet();
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
        if (isLikelyClarification(content) &&
            !unsupportedLegacyToolMarkup) {
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
                '${unsupportedLegacyToolMarkup ? '上一轮输出了无法解析或本轮未开放的文本工具调用；没有执行查询、生成确认卡或写入数据。请使用本轮可用的 propose_cdt_actions 工具。' : ''}'
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
        if (isLikelyClarification(content) &&
            !unsupportedLegacyToolMarkup) {
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
                '${unsupportedLegacyToolMarkup ? '上一轮输出了无法解析或本轮未开放的文本工具调用；没有执行查询、生成确认卡或写入数据。请根据用户的原始请求使用本轮可用的 propose_* 工具，信息不足时再向用户追问。' : ''}'
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
      if (calls.isEmpty &&
          legacyCalls.hadToolMarkup &&
          !hasPlanningTool &&
          !hasWriteProposalTool) {
        final unseenContent = content.startsWith(streamedVisibleContent)
            ? content.substring(streamedVisibleContent.length)
            : content;
        if (unseenContent.isNotEmpty) {
          yield AiChatStreamChunk(content: unseenContent);
        }
        return;
      }
      final missingWriteProposalNames = requiredWriteProposalNames.difference(
        completedWriteProposalNames,
      );
      if (calls.isEmpty && missingWriteProposalNames.isNotEmpty) {
        if (isLikelyClarification(content)) {
          if (content.isNotEmpty) yield AiChatStreamChunk(content: content);
          return;
        }
        if (!missingWriteProposalRepairAttempted) {
          missingWriteProposalRepairAttempted = true;
          actionProposalRepairAttempted = true;
          history.add({
            'role': 'assistant',
            'content': content,
            if (includeReasoningContent) 'reasoning_content': reasoning,
          });
          history.add({
            'role': 'system',
            'content':
                '${completedWriteProposalNames.isEmpty ? '用户明确要求写入数据，但目前还没有有效写入提案。' : '已有有效写入提案及确认卡，尚缺少用户明确要求的提案：${missingWriteProposalNames.join('、')}。'}'
                '${completedWriteProposalNames.isEmpty ? '现在提交尚缺的提案工具；' : '已有确认卡会保留；现在只调用尚缺的提案工具，不要重复已提交的操作。'}'
                '如果缺少信息则向用户追问，不要声称所有操作都已生成。',
          });
          continue;
        }
        yield AiChatStreamChunk(
          content: missingWriteProposalFailure(missingWriteProposalNames),
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
                roundAllowedToolNames.contains(call.name) &&
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
            roundAllowedToolNames.contains(call.name) &&
            call.name.startsWith('propose_'),
      );
      if (proposalsOnly &&
          invalidWriteProposals.isEmpty &&
          missingWriteProposalNamesAfterRound.isEmpty) {
        // Write proposal prose is buffered so the UI cannot show a premature
        // success claim. Preserve only the model-authored suggestion block;
        // the chat screen still grounds and deduplicates it before display.
        final suggestions = AiActionParser.extractSuggestions(content);
        if (suggestions.isNotEmpty) {
          yield AiChatStreamChunk(
            content:
                '[SUGGEST_START]${jsonEncode(suggestions)}[SUGGEST_END]',
          );
        }
        return;
      }
      if (finalRound &&
          calls.any(
            (call) =>
                roundAllowedToolNames.contains(call.name) &&
                AiQueryToolService.toolNames.contains(call.name),
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
        final requiredProposalNotYetSubmitted =
            requiredWriteProposalNames.contains(call.name) &&
            !completedWriteProposalNames.contains(call.name);
        Map<String, dynamic> result;
        if (!roundAllowedToolNames.contains(call.name)) {
          result = {'ok': false, 'error': '本轮未开放此工具'};
        } else if (!usedIds.add(call.id)) {
          result = {'ok': false, 'error': '重复的工具调用ID，未再次执行'};
        } else if (callCount > maxCalls && !requiredProposalNotYetSubmitted) {
          result = {'ok': false, 'error': '本轮工具调用次数达到上限'};
        } else if (AiQueryToolService.toolNames.contains(call.name) &&
            resultChars > AiToolResultContext.maxTurnChars - 400) {
          result = {'ok': false, 'error': '本轮数据预算达到上限，请根据已有结果回答'};
        } else if (AiQueryToolService.toolNames.contains(call.name)) {
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
            completedWriteProposalNames.add(call.name);
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
        if (AiQueryToolService.toolNames.contains(call.name)) {
          queriedReferenceDomains.addAll(_queryReferenceDomains(call));
        }
        if (AiQueryToolService.toolNames.contains(call.name) &&
            _queryReturnsReferenceIds(call, result)) {
          referenceReadyDomains.addAll(_queryReferenceDomains(call));
          if (call.name == 'query_finance' &&
              _queryReferenceDomains(call).contains('finance_transactions')) {
            final returnedTransactionIds = _financeTransactionIdsFromQuery(
              result,
            );
            if (returnedTransactionIds.isNotEmpty) {
              validatedFinanceTransactionIds ??= <String>{};
              validatedFinanceTransactionIds.addAll(returnedTransactionIds);
            }
          }
          if (call.name == 'query_finance' &&
              _queryReferenceDomains(call).contains('finance_catalog')) {
            final returnedCatalogIds = _financeCatalogIdsFromQuery(result);
            if (returnedCatalogIds.isNotEmpty) {
              validatedFinanceCatalogIdsByKind ??= <String, Set<String>>{};
              for (final entry in returnedCatalogIds.entries) {
                validatedFinanceCatalogIdsByKind.putIfAbsent(
                  entry.key,
                  () => <String>{},
                ).addAll(entry.value);
              }
            }
          }
          if (actionProposalRepairAttempted &&
              pendingReferenceDomains.isNotEmpty &&
              pendingReferenceDomains.every(referenceReadyDomains.contains)) {
            actionRepairQueriesUsed = true;
          }
        }
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
        final allDependencyQueriesSucceeded =
            pendingReferenceDomains.isNotEmpty &&
            pendingReferenceDomains.every(referenceReadyDomains.contains);
        final canRetryWithReadyReferences =
            actionProposalRepairAttempted &&
            deferredReferenceProposal &&
            allDependencyQueriesSucceeded &&
            actionRepairQueriesUsed &&
            !referenceProposalRetryUsed;
        if ((actionProposalRepairAttempted &&
                !canRetryWithReadyReferences) ||
            round >= maxQueryRounds + 1) {
          yield AiChatStreamChunk(
            content: deferredReferenceProposal
                ? '本轮查询与依赖现有对象的写入提案仍未能分步完成；应用没有生成该确认卡，也没有写入数据。请重试，或先查询并确认具体对象。'
                : completedWriteProposalNames.isEmpty
                ? '模型返回的写入参数仍不符合本轮工具格式；应用没有生成有效确认卡，也没有写入数据。请重试或补充信息。'
                : '部分写入函数参数仍不符合本轮工具格式；无效调用没有执行。请检查已生成的操作卡，并补充或重试缺失的操作。',
          );
          return;
        }
        if (canRetryWithReadyReferences) referenceProposalRetryUsed = true;
        if (deferredReferenceProposal && allDependencyQueriesSucceeded) {
          actionRepairQueriesUsed = true;
        }
        actionProposalRepairAttempted = true;
        proposalsProduced = false;
        history.add({
          'role': 'system',
          'content':
              '${deferredReferenceProposal ? '上一轮在同一批函数调用中同时查询和提交了依赖现有对象的写入提案；App已执行只读查询，但没有生成该提案的确认卡。' : '上一轮这些写入函数调用未通过参数校验：${invalidWriteProposalIssues.join('；')}。'}'
              'App没有执行无效调用，也没有写入任何数据。'
              '${deferredReferenceProposal && allDependencyQueriesSucceeded ? '查询结果已返回；现在只根据结果中的真实ID重新调用对应提案工具，不要再次查询。' : deferredReferenceProposal ? '相关查询结果有失败或不完整；不要猜测对象ID，先重试查询或向用户追问。' : validWriteProposalNames.isEmpty ? '现在请修正参数并重新调用对应提案工具。' : '其他有效提案已保留；不要重复它们，只补齐无效调用对应的提案。'}'
              '如果信息不足或意图有歧义，先向用户追问；不要声称已经完成或保存。',
        });
        continue;
      }
      final missingAfterCalls = requiredWriteProposalNames.difference(
        completedWriteProposalNames,
      );
      if (missingAfterCalls.isNotEmpty &&
          calls.any((call) => _writeProposalToolNames.contains(call.name))) {
        if (!missingWriteProposalRepairAttempted) {
          missingWriteProposalRepairAttempted = true;
          actionProposalRepairAttempted = true;
          history.add({
            'role': 'system',
            'content':
                '已有有效写入提案及确认卡，尚缺少用户明确要求的提案：${missingAfterCalls.join('、')}。'
                '已有确认卡会保留；现在只调用尚缺的提案工具，不要重复已提交的操作。'
                '如果缺少信息则向用户追问，不要声称所有操作都已生成。',
          });
          continue;
        }
        yield AiChatStreamChunk(
          content: missingWriteProposalFailure(missingAfterCalls),
        );
        return;
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

  static const _cdtActionQueryDomains = {
    'update_todo': {'todos'},
    'complete_todo': {'todos'},
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

  static Set<String> _proposalReferenceDomains(AiChatFunctionCall call) {
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
      (field) => record[field] is List &&
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
        (draft) => hasReference(
          draft,
          const [
            'categoryUuid',
            'category_uuid',
            'paymentMethodUuid',
            'payment_method_uuid',
          ],
        ),
      )
          ? const {'finance_catalog'}
          : const {};
    }
    if (call.name != 'propose_cdt_actions' ||
        arguments['actions'] is! List) {
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
          if (hasReference(action, const [
                'todoId',
                'todo_id',
                'todoUuid',
              ]) ||
              recordsFor(action, 'blocks').any(
                (block) => hasReference(block, const [
                  'todoId',
                  'todo_id',
                  'todoUuid',
                ]),
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
                (log) => hasListReference(log, const [
                  'tagUuids',
                  'tagIds',
                ]),
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

  static Set<String> _matchingQueryCallIdsForProposal(
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

  static Set<String> _queryReferenceDomains(AiChatFunctionCall call) {
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

  static bool _queryReturnsReferenceIds(
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

  static String? _writeProposalValidationIssue(
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

  static String? _countdownMutationRoutingIssue(
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

  static String? _writeProposalSemanticIssue(
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
        if (rawRecurrenceEnd != null &&
            !_isStrictDateOnly(rawRecurrenceEnd)) {
          return 'recurrenceEndDate必须是有效的yyyy-MM-dd日期';
        }
        if (rawRecurrenceEnd != null &&
            dueDate != null &&
            _parseStrictLocalDateTime(rawRecurrenceEnd)!.isBefore(
              DateTime(dueDate.year, dueDate.month, dueDate.day),
            )) {
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

  static String? _validateFinanceDraftProposal(
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

  static String? _validateFinanceActionProposal(
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
        if (action.containsKey('amount') ||
            action.containsKey('amount_minor')) {
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

  static String? _validateFinanceCatalogReference(
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

  static Set<String> _financeTransactionIdsFromQuery(
    Map<String, dynamic> result,
  ) {
    final items = result['items'];
    if (items is! List) return const {};
    return items.whereType<Map>().map((item) {
      return (item['transactionId'] ?? item['transaction_id'] ?? item['id'])
          ?.toString()
          .trim();
    }).whereType<String>().where((id) => id.isNotEmpty).toSet();
  }

  static Map<String, Set<String>> _financeCatalogIdsFromQuery(
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

  static String? _validateFinanceAmount(Map record) {
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

  static DateTime? _parseStrictLocalDateTime(Object? value) {
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

  static bool _isStrictDateOnly(Object? value) =>
      value is String &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.trim()) &&
      _parseStrictLocalDateTime(value) != null;

  static String? _validateCdtCreationAction(
    Map action, {
    Set<String>? knownTodoIds,
    Map<String, Set<String>>? knownReferenceIdsByDomain,
  }) {
    final actionName = action['action']?.toString();
    final recordsField = switch (actionName) {
      'create_todo' => 'todos',
      'create_schedule' => 'schedules',
      'create_time_log' => 'logs',
      'create_countdown' => 'countdowns',
      'create_plan_block' => 'blocks',
      'create_habit' => 'habits',
      'split_todo' => 'todos',
      'merge_todos' => 'todo',
      'create_todo_group' => 'groups',
      'create_pomodoro_tag' => 'tags',
      _ => null,
    };
    if (recordsField == null) return null;
    final rawRecords = action[recordsField];
    final records = rawRecords is List
        ? rawRecords.whereType<Map>().toList(growable: false)
        : [action];
    if (records.isEmpty) return '$actionName 至少需要一条有效记录';

    for (final record in records) {
      final title = (record['title'] ?? record['name'])?.toString().trim();
      switch (actionName) {
        case 'create_todo':
          final groupIds = [
            if (record['groupId'] != null) record['groupId'],
            if (record['group_id'] != null) record['group_id'],
          ]
              .map((value) => value.toString().trim())
              .where((id) => id.isNotEmpty)
              .toSet();
          if (groupIds.length > 1) {
            return 'create_todo 的groupId与group_id不能互相冲突';
          }
          final groupId = groupIds.isEmpty ? null : groupIds.single;
          final knownGroupIds = knownReferenceIdsByDomain?['todo_groups'];
          if (groupId != null &&
              knownGroupIds != null &&
              !knownGroupIds.contains(groupId)) {
            return 'create_todo 引用了当前不存在的分类，请先查询并选择真实分类';
          }
          break;
        case 'split_todo':
          final sourceTodoId = [
            action['sourceTodoId'],
            action['todoId'],
            action['source_id'],
          ].any((value) => value?.toString().trim().isNotEmpty == true);
          if (!sourceTodoId) return 'split_todo必须提供sourceTodoId';
          final splitTodos = action['todos'];
          if (splitTodos is! List || splitTodos.isEmpty) {
            return 'split_todo必须包含至少一条拆分后的待办';
          }
          if (splitTodos.any(
            (todo) =>
                todo is! Map ||
                todo['title']?.toString().trim().isNotEmpty != true,
          )) {
            return 'split_todo中的每条新待办都必须包含非空标题';
          }
          break;
        case 'merge_todos':
          final mergedTodo = action['todo'];
          if (mergedTodo is! Map ||
              mergedTodo['title']?.toString().trim().isNotEmpty != true) {
            return 'merge_todos必须提供包含非空title的新todo对象';
          }
          break;
        case 'create_schedule':
          if (title == null || title.isEmpty) {
            return 'create_schedule 每项都必须包含日程标题';
          }
          final rawDate = record['date'];
          final rawStart = record['startTime'];
          final rawEnd = record['dueDate'] ?? record['endTime'];
          final date = _parseStrictLocalDateTime(rawDate);
          final start = _parseStrictLocalDateTime(rawStart);
          final end = _parseStrictLocalDateTime(rawEnd);
          if (rawDate != null && rawDate.toString().trim().isNotEmpty && date == null) {
            return 'create_schedule 的date必须是有效日期';
          }
          if (rawStart != null &&
              rawStart.toString().trim().isNotEmpty &&
              start == null) {
            return 'create_schedule 的startTime必须是有效本地时间';
          }
          if (date != null &&
              start != null &&
              (date.year != start.year ||
                  date.month != start.month ||
                  date.day != start.day)) {
            return 'create_schedule 的date必须与startTime属于同一天';
          }
          if ((date == null && start == null) ||
              (rawEnd != null &&
                  rawEnd.toString().trim().isNotEmpty &&
                  end == null) ||
              (end != null && (start == null || !end.isAfter(start)))) {
            return 'create_schedule 需要有效date或startTime；填写结束时间时也必须晚于开始时间';
          }
          break;
        case 'create_time_log':
          if (title == null || title.isEmpty) {
            return 'create_time_log 每项都必须包含专注内容标题';
          }
          final tagAliases = [
            if (record['tagUuids'] is List)
              (record['tagUuids'] as List)
                  .whereType<String>()
                  .map((id) => id.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet(),
            if (record['tagIds'] is List)
              (record['tagIds'] as List)
                  .whereType<String>()
                  .map((id) => id.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet(),
          ];
          if (tagAliases.length > 1 &&
              tagAliases.skip(1).any(
                (ids) => !_sameStringSet(tagAliases.first, ids),
              )) {
            return 'create_time_log 的tagUuids与tagIds不能互相冲突';
          }
          final tagIds = tagAliases.isEmpty ? const <String>{} : tagAliases.first;
          final knownTagIds = knownReferenceIdsByDomain?['pomodoro_tags'];
          if (knownTagIds != null &&
              tagIds.any((id) => !knownTagIds.contains(id))) {
            return 'create_time_log 引用了当前不存在的番茄标签，请先查询并选择真实标签';
          }
          final rawStart = record['startTime'];
          final rawEnd = record['dueDate'] ?? record['endTime'];
          final start = _parseStrictLocalDateTime(rawStart);
          final end = _parseStrictLocalDateTime(rawEnd);
          final duration = _toPositiveInt(record['durationMinutes']);
          if (rawStart == null || start == null) {
            return 'create_time_log 每项都必须包含有效startTime';
          }
          if ((rawEnd != null && end == null) ||
              (end != null && !end.isAfter(start)) ||
              (rawEnd == null && duration == null)) {
            return 'create_time_log 每项都需要晚于开始时间的dueDate/endTime，或正数durationMinutes';
          }
          break;
        case 'create_countdown':
          if (title == null || title.isEmpty) {
            return 'create_countdown 每项都必须包含事件标题';
          }
          final rawTarget = record['dueDate'] ?? record['startTime'];
          if (rawTarget == null ||
              _parseStrictLocalDateTime(rawTarget) == null) {
            return 'create_countdown 每项都必须包含有效dueDate';
          }
          break;
        case 'create_plan_block':
          final newTodoTitle = record['newTodoTitle']?.toString().trim() ?? '';
          final todoAliases = [
            if (record['todoId'] != null) record['todoId'],
            if (record['todo_id'] != null) record['todo_id'],
            if (record['todoUuid'] != null) record['todoUuid'],
          ]
              .map((value) => value.toString().trim())
              .where((id) => id.isNotEmpty)
              .toSet();
          if (todoAliases.length > 1) {
            return 'create_plan_block 的待办ID字段不能互相冲突';
          }
          final todoId = todoAliases.isNotEmpty;
          final referencedTodoId =
              todoAliases.isEmpty ? null : todoAliases.first;
          if (referencedTodoId != null &&
              knownTodoIds != null &&
              !knownTodoIds.contains(referencedTodoId)) {
            return 'create_plan_block 引用了当前不存在的todoId，请先查询并选择真实待办';
          }
          if (newTodoTitle.isEmpty && !todoId) {
            return 'create_plan_block 每项都必须引用已有todoId或提供newTodoTitle';
          }
          if (newTodoTitle.isNotEmpty && todoId) {
            return '新规划事项使用newTodoTitle时不要同时填写todoId';
          }
          final rawStart = record['startTime'];
          final rawEnd = record['dueDate'] ?? record['endTime'];
          final start = _parseStrictLocalDateTime(rawStart);
          final end = _parseStrictLocalDateTime(rawEnd);
          final duration = _toPositiveInt(record['durationMinutes']);
          if (start == null ||
              (rawEnd != null && end == null) ||
              (end == null && duration == null) ||
              (end != null && !end.isAfter(start)) ||
              (end == null &&
                  duration != null &&
                  !start.add(Duration(minutes: duration)).isAfter(start))) {
            return 'create_plan_block 每项都需要有效startTime，以及晚于开始时间的dueDate或正数durationMinutes';
          }
          break;
        case 'create_habit':
          if (title == null || title.isEmpty) {
            return 'create_habit 每项都必须包含习惯名称';
          }
          final sourceType =
              (record['sourceType'] ??
                      record['habitSourceType'] ??
                      record['source_type'] ??
                      action['sourceType'] ??
                      action['habitSourceType'])
                  ?.toString();
          const sourceTypes = {
            'quantityCheckIn',
            'timeCheckIn',
            'durationCheckIn',
            'pomodoroTag',
            'recurringTodo',
          };
          if (sourceType == null || !sourceTypes.contains(sourceType)) {
            return 'create_habit 每项都必须指定有效sourceType';
          }
          final periodType =
              (record['periodType'] ?? record['habitPeriodType'])?.toString();
          const periodTypes = {
            'daily',
            'weekly',
            'weekdays',
            'monthly',
            'custom',
          };
          if (periodType == null || !periodTypes.contains(periodType)) {
            return 'create_habit 每项都必须指定有效periodType';
          }
          if (periodType == 'custom' &&
              _toPositiveInt(record['customIntervalDays']) == null) {
            return 'custom习惯必须包含正数customIntervalDays';
          }
          final sourceIdAliases = [
            for (final field in <String>[
              'sourceIds',
              'source_ids',
              'habitSourceIds',
              'habit_source_ids',
              if (sourceType == 'pomodoroTag') 'tagUuids',
              if (sourceType == 'pomodoroTag') 'tagIds',
            ])
              if (record[field] is List)
                (record[field] as List)
                    .whereType<String>()
                    .map((id) => id.trim())
                    .where((id) => id.isNotEmpty)
                    .toSet(),
          ];
          if (sourceIdAliases.length > 1 &&
              sourceIdAliases.skip(1).any(
                (ids) => !_sameStringSet(sourceIdAliases.first, ids),
              )) {
            return 'create_habit 的sourceIds字段不能互相冲突';
          }
          final sourceIds = sourceIdAliases.isEmpty
              ? const <String>{}
              : sourceIdAliases.first;
          if (sourceType == 'pomodoroTag') {
            final knownTagIds = knownReferenceIdsByDomain?['pomodoro_tags'];
            if (knownTagIds != null &&
                sourceIds.any((id) => !knownTagIds.contains(id))) {
              return 'create_habit 引用了当前不存在的番茄标签，请先查询并选择真实标签';
            }
          } else if (sourceType == 'recurringTodo' && sourceIds.isNotEmpty) {
            final knownSeriesIds =
                knownReferenceIdsByDomain?['recurring_todo_series'];
            if (knownSeriesIds != null &&
                sourceIds.any((id) => !knownSeriesIds.contains(id))) {
              return '完成型习惯引用的sourceIds必须是当前有效的循环待办系列';
            }
          }
          final rawWeekdaysMask =
              record['weekdaysMask'] ?? record['weekdays_mask'];
          final weekdaysMask = _toInt(rawWeekdaysMask);
          if (rawWeekdaysMask != null &&
              (weekdaysMask == null ||
                  weekdaysMask < 1 ||
                  weekdaysMask > 127)) {
            return 'weekdaysMask必须是1至127之间的有效掩码';
          }
          final rawDayBoundaryMinute =
              record['dayBoundaryMinute'] ?? record['day_boundary_minute'];
          final dayBoundaryMinute = _toInt(rawDayBoundaryMinute);
          if (rawDayBoundaryMinute != null &&
              (dayBoundaryMinute == null ||
                  dayBoundaryMinute < 0 ||
                  dayBoundaryMinute >= 1440)) {
            return 'dayBoundaryMinute必须是0至1439的分钟值';
          }
          final rawTolerance =
              record['timeToleranceMinutes'] ??
              record['time_tolerance_minutes'];
          final tolerance = _toInt(rawTolerance);
          if (rawTolerance != null &&
              (tolerance == null || tolerance < 0)) {
            return 'timeToleranceMinutes必须是非负整数';
          }
          final targetValue = _toPositiveDouble(record['targetValue']);
          switch (sourceType) {
            case 'quantityCheckIn':
              if (targetValue == null) return '数量习惯必须包含正数targetValue';
              if (record['unit']?.toString().trim().isNotEmpty != true &&
                  record['habitUnit']?.toString().trim().isNotEmpty != true) {
                return '数量习惯必须包含unit';
              }
              break;
            case 'timeCheckIn':
              final targetMinute = _toInt(
                record['targetTimeMinute'] ?? record['targetTime'],
              );
              if (targetMinute == null ||
                  targetMinute < 0 ||
                  targetMinute >= 1440) {
                return '时间点习惯必须包含0至1439的targetTimeMinute';
              }
              break;
            case 'durationCheckIn':
              if (_toPositiveInt(record['durationMinutes']) == null) {
                return '时长习惯必须包含正数durationMinutes';
              }
              break;
            case 'pomodoroTag':
              if (sourceIds.isEmpty ||
                  _toPositiveInt(record['durationMinutes']) == null) {
                return '番茄标签习惯必须引用真实sourceIds并包含正数durationMinutes';
              }
              break;
          }
          break;
        case 'create_todo_group':
          if (title == null || title.isEmpty) {
            return 'create_todo_group 每项都必须包含分类名称';
          }
          break;
        case 'create_pomodoro_tag':
          if (title == null || title.isEmpty) {
            return 'create_pomodoro_tag 每项都必须包含标签名称';
          }
          break;
      }
    }
    return null;
  }

  static String? _validateCdtMutationAction(
    Map action, {
    required String requestText,
    Map<String, Set<String>>? knownReferenceIdsByDomain,
  }) {
    final actionName = action['action']?.toString();
    final deletesSourceTodos = actionName == 'split_todo'
        ? action['deleteSource'] == true ||
              action['deleteSourceTodos'] == true ||
              action['deleteSources'] == true
        : actionName == 'merge_todos' &&
              (action['deleteSources'] == true ||
                  action['deleteSourceTodos'] == true ||
                  action['deleteSource'] == true);
    if (deletesSourceTodos &&
        !_explicitlyRequestsSourceTodoDeletion(requestText)) {
      return '只有用户明确要求删除拆分或合并前的源待办时，才能设置删除源待办';
    }

    const mutableFieldsByAction = <String, Set<String>>{
      'update_todo': {
        'title',
        'remark',
        'timeMode',
        'dueDate',
        'groupId',
        'reminderMinutes',
        'recurrence',
        'customIntervalDays',
        'recurrenceEndDate',
      },
      'categorize_todo': {'groupId'},
      'reschedule_todo': {'timeMode', 'dueDate'},
      'bulk_reschedule': {'timeMode', 'dueDate'},
      'update_schedule': {
        'title',
        'date',
        'startTime',
        'endTime',
        'location',
        'remark',
        'reminderMinutes',
        'recurrence',
        'customIntervalDays',
        'recurrenceEndDate',
      },
      'update_plan_block': {
        'title',
        'startTime',
        'dueDate',
        'endTime',
        'durationMinutes',
        'remark',
        'reminderMinutes',
      },
      'reschedule_plan_blocks': {
        'startTime',
        'dueDate',
        'endTime',
        'durationMinutes',
      },
      'update_time_log': {
        'title',
        'startTime',
        'dueDate',
        'endTime',
        'durationMinutes',
        'remark',
        'tagUuids',
        'tagIds',
      },
      'update_countdown': {'title', 'dueDate', 'startTime'},
      'update_todo_group': {'name', 'title'},
      'update_pomodoro_tag': {'name', 'title', 'color'},
    };
    final mutableFields = mutableFieldsByAction[actionName];
    if (mutableFields != null) {
      final rawUpdates = action['updates'] ?? action['blocks'];
      if (rawUpdates is! List || rawUpdates.isEmpty) {
        return '$actionName至少需要一条updates记录';
      }
      for (final rawUpdate in rawUpdates) {
        if (rawUpdate is! Map) return '$actionName的每项updates都必须是对象';
        if (!mutableFields.any(rawUpdate.containsKey)) {
          return '$actionName每项都必须包含至少一个要修改的字段';
        }
        if (actionName == 'update_todo' ||
            actionName == 'categorize_todo') {
          for (final field in const ['groupId', 'group_id']) {
            if (rawUpdate.containsKey(field) &&
                rawUpdate[field] is String &&
                (rawUpdate[field] as String).trim().isEmpty) {
              return '$actionName的分类ID不能为空字符串；清除分类时请使用null';
            }
          }
          final groupIds = [
            if (rawUpdate['groupId'] != null)
              rawUpdate['groupId'].toString().trim(),
            if (rawUpdate['group_id'] != null)
              rawUpdate['group_id'].toString().trim(),
          ].where((id) => id.isNotEmpty).toSet();
          if (groupIds.length > 1) {
            return '$actionName的groupId与group_id不能互相冲突';
          }
          final groupId = groupIds.isEmpty ? null : groupIds.single;
          final knownGroupIds = knownReferenceIdsByDomain?['todo_groups'];
          if (groupId != null &&
              knownGroupIds != null &&
              !knownGroupIds.contains(groupId)) {
            return '$actionName引用了当前不存在的分类，请先查询并选择真实分类';
          }
        }
        if (actionName == 'update_time_log') {
          final tagAliases = [
            if (rawUpdate['tagUuids'] is List)
              (rawUpdate['tagUuids'] as List)
                  .whereType<String>()
                  .map((id) => id.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet(),
            if (rawUpdate['tagIds'] is List)
              (rawUpdate['tagIds'] as List)
                  .whereType<String>()
                  .map((id) => id.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet(),
          ];
          if (tagAliases.length > 1 &&
              tagAliases.skip(1).any(
                (ids) => !_sameStringSet(tagAliases.first, ids),
              )) {
            return 'update_time_log的tagUuids与tagIds不能互相冲突';
          }
          final tagIds =
              tagAliases.isEmpty ? const <String>{} : tagAliases.first;
          final knownTagIds = knownReferenceIdsByDomain?['pomodoro_tags'];
          if (knownTagIds != null &&
              tagIds.any((id) => !knownTagIds.contains(id))) {
            return 'update_time_log引用了当前不存在的番茄标签，请先查询并选择真实标签';
          }
        }
      }
    }

    if (actionName != 'update_habit' && actionName != 'delete_habit') {
      return null;
    }
    final rawUpdates = action['updates'];
    if (rawUpdates is! List || rawUpdates.isEmpty) {
      return '$actionName至少需要一条updates记录';
    }
    for (final rawUpdate in rawUpdates) {
      if (rawUpdate is! Map) return '$actionName的每项updates都必须是对象';
      final title = rawUpdate['title']?.toString().trim() ?? '';
      if (title.isEmpty) {
        return '$actionName每项都必须提供习惯名称，供用户在确认卡中核对';
      }
    }
    if (actionName == 'delete_habit') return null;
    const mutableHabitFields = {
      'name',
      'icon',
      'displayMode',
      'defaultFocusMinutes',
      'targetValue',
      'unit',
      'durationMinutes',
      'targetTimeMinute',
      'timeComparison',
      'timeToleranceMinutes',
      'periodType',
      'weekdaysMask',
      'customIntervalDays',
      'dayBoundaryMinute',
      'quickValues',
      'reminderPolicy',
    };
    const ruleFields = {
      'targetValue',
      'unit',
      'durationMinutes',
      'targetTimeMinute',
      'timeComparison',
      'timeToleranceMinutes',
      'periodType',
      'weekdaysMask',
      'customIntervalDays',
      'dayBoundaryMinute',
      'quickValues',
      'reminderPolicy',
    };
    for (final rawUpdate in rawUpdates) {
      if (rawUpdate is! Map) return 'update_habit的每项updates都必须是对象';
      final update = Map<String, dynamic>.from(rawUpdate);
      if (!mutableHabitFields.any(update.containsKey)) {
        return 'update_habit必须至少提供一个要修改的习惯字段';
      }
      if (update.containsKey('name') &&
          update['name']?.toString().trim().isEmpty == true) {
        return '习惯名称不能为空';
      }
      if (update.containsKey('displayMode') &&
          !const {'habitOnly', 'todoOnly', 'both'}.contains(
            update['displayMode'],
          )) {
        return 'displayMode必须是habitOnly、todoOnly或both';
      }
      if (update.containsKey('defaultFocusMinutes')) {
        final minutes = _toPositiveInt(update['defaultFocusMinutes']);
        if (minutes == null || minutes > 240) {
          return 'defaultFocusMinutes必须是1至240的正整数';
        }
      }
      if (update.containsKey('targetValue') &&
          _toPositiveDouble(update['targetValue']) == null) {
        return 'targetValue必须是正数';
      }
      if (update.containsKey('unit') &&
          update['unit']?.toString().trim().isEmpty == true) {
        return 'unit不能为空';
      }
      if (update.containsKey('durationMinutes') &&
          _toPositiveInt(update['durationMinutes']) == null) {
        return 'durationMinutes必须是正整数';
      }
      if (update.containsKey('targetTimeMinute')) {
        final minute = _toInt(update['targetTimeMinute']);
        if (minute == null || minute < 0 || minute >= 1440) {
          return 'targetTimeMinute必须是0至1439的分钟值';
        }
      }
      if (update.containsKey('timeComparison') &&
          !const {'before', 'after'}.contains(update['timeComparison'])) {
        return 'timeComparison必须是before或after';
      }
      if (update.containsKey('timeToleranceMinutes')) {
        final tolerance = _toInt(update['timeToleranceMinutes']);
        if (tolerance == null || tolerance < 0) {
          return 'timeToleranceMinutes必须是非负整数';
        }
      }
      if (update.containsKey('periodType') &&
          !const {'daily', 'weekly', 'weekdays', 'monthly', 'custom'}
              .contains(update['periodType'])) {
        return 'periodType不是支持的习惯周期';
      }
      if (update['periodType'] == 'custom' &&
          _toPositiveInt(update['customIntervalDays']) == null) {
        return 'custom周期必须包含正数customIntervalDays';
      }
      if (update.containsKey('customIntervalDays') &&
          _toPositiveInt(update['customIntervalDays']) == null) {
        return 'customIntervalDays必须是正整数';
      }
      if (update['periodType'] == 'weekdays' &&
          !update.containsKey('weekdaysMask')) {
        return 'periodType为weekdays时必须包含weekdaysMask';
      }
      if (update.containsKey('weekdaysMask')) {
        final mask = _toInt(update['weekdaysMask']);
        if (mask == null || mask < 1 || mask > 127) {
          return 'weekdaysMask必须是1至127之间的有效掩码';
        }
      }
      if (update.containsKey('dayBoundaryMinute')) {
        final minute = _toInt(update['dayBoundaryMinute']);
        if (minute == null || minute < 0 || minute >= 1440) {
          return 'dayBoundaryMinute必须是0至1439的分钟值';
        }
      }
      if (update.containsKey('quickValues')) {
        final values = update['quickValues'];
        if (values is! List ||
            values.length > 4 ||
            values.any((value) => _toPositiveInt(value) == null)) {
          return 'quickValues必须是最多4个正整数的数组';
        }
      }
      if (update.containsKey('reminderPolicy')) {
        final policy = update['reminderPolicy'];
        if (policy is! Map) return 'reminderPolicy必须是对象';
        final fixedTimes = policy['fixedTimes'] ?? policy['fixed_times'];
        if (fixedTimes != null &&
            (fixedTimes is! List ||
                fixedTimes.any((value) {
                  final minute = _toInt(value);
                  return minute == null || minute < 0 || minute >= 1440;
                }))) {
          return 'reminderPolicy.fixedTimes必须是0至1439的分钟数组';
        }
      }
      final effectiveFromOption = update['effectiveFromOption'];
      if (effectiveFromOption != null &&
          !const {'today', 'nextPeriod', 'all'}.contains(effectiveFromOption)) {
        return 'effectiveFromOption必须是today、nextPeriod或all';
      }
      if (effectiveFromOption == 'all' &&
          !RegExp(r'全部历史|所有历史|历史目标全部|所有周期目标').hasMatch(requestText)) {
        return '只有用户明确要求覆盖全部历史目标时才能使用effectiveFromOption=all';
      }
      if (effectiveFromOption == 'nextPeriod' &&
          !RegExp(r'下个周期|下一个周期|下一周期|下周|下个月|下月|下期')
              .hasMatch(requestText)) {
        return '只有用户明确要求下个周期生效时才能使用effectiveFromOption=nextPeriod';
      }
      if (update.containsKey('sourceType') ||
          update.containsKey('habitSourceType') ||
          update.containsKey('sourceIds') ||
          update.containsKey('source_ids')) {
        return '不能通过update_habit更换习惯来源类型或来源';
      }
      if (update.containsKey('effectiveFromOption') &&
          !ruleFields.any(update.containsKey)) {
        return 'effectiveFromOption只能与习惯规则修改一起使用';
      }
    }
    return null;
  }

  static bool _explicitlyRequestsSourceTodoDeletion(String requestText) {
    const sourceTodo =
        r'(?:原(?:有|来|始)?(?:的)?|旧(?:的)?|来源|源)(?:待办|任务|事项|项)';
    return RegExp(
      '(?:删除|删掉|移除|清除|去掉)[^。！？\\n]{0,4}$sourceTodo|'
      '$sourceTodo[^。！？\\n]{0,4}(?:删除|删掉|移除|清除|去掉)|'
      '不保留[^。！？\\n]{0,6}$sourceTodo',
    ).hasMatch(requestText);
  }

  static String? _validateCdtActionReference(
    Map action, {
    Set<String>? knownTodoIds,
    Set<String>? knownHabitIds,
    Map<String, Set<String>>? knownReferenceIdsByDomain,
  }) {
    final actionName = action['action']?.toString();
    final normalizedKnownTodoIds = knownTodoIds
        ?.map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final normalizedKnownHabitIds = knownHabitIds
        ?.map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final normalizedDomainIds = knownReferenceIdsByDomain?.map(
      (domain, ids) => MapEntry(
        domain,
        ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet(),
      ),
    );
    if (actionName == 'start_pomodoro') {
      final todoIds = [
        if (action['todoId'] != null) action['todoId'],
        if (action['todo_id'] != null) action['todo_id'],
      ]
          .map((value) => value.toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (todoIds.length > 1) {
        return 'start_pomodoro的todoId与todo_id不能互相冲突';
      }
      final todoId = todoIds.isEmpty ? null : todoIds.single;
      if (todoId != null &&
          normalizedKnownTodoIds != null &&
          !normalizedKnownTodoIds.contains(todoId)) {
        return 'start_pomodoro引用了当前不存在的todoId，请先查询并选择真实待办';
      }
      final tagAliases = [
        if (action['tagUuids'] is List)
          (action['tagUuids'] as List)
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet(),
        if (action['tagIds'] is List)
          (action['tagIds'] as List)
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet(),
      ];
      if (tagAliases.length > 1 &&
          tagAliases.skip(1).any(
            (ids) => !_sameStringSet(tagAliases.first, ids),
          )) {
        return 'start_pomodoro的tagUuids与tagIds不能互相冲突';
      }
      final tagIds = tagAliases.isEmpty ? const <String>{} : tagAliases.first;
      final knownTagIds = normalizedDomainIds?['pomodoro_tags'];
      if (knownTagIds != null &&
          tagIds.any((id) => !knownTagIds.contains(id))) {
        return 'start_pomodoro引用了当前不存在的番茄标签，请先查询并选择真实标签';
      }
      return null;
    }
    if (actionName == 'merge_todos') {
      final suppliedSourceAliases = [
        if (action['sourceTodoIds'] is List)
          (action['sourceTodoIds'] as List)
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet(),
        if (action['todoIds'] is List)
          (action['todoIds'] as List)
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet(),
      ];
      if (suppliedSourceAliases.length > 1 &&
          (suppliedSourceAliases.first.length !=
                  suppliedSourceAliases.last.length ||
              !suppliedSourceAliases.first.containsAll(
                suppliedSourceAliases.last,
              ))) {
        return 'merge_todos的sourceTodoIds与todoIds不能互相冲突';
      }
      final sourceIds = action['sourceTodoIds'] ?? action['todoIds'];
      if (sourceIds is! List) {
        return 'merge_todos必须包含sourceTodoIds数组';
      }
      final ids = sourceIds
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (ids.length < 2) {
        return 'merge_todos必须引用至少两个本轮上下文中的真实待办ID';
      }
      if (normalizedKnownTodoIds != null &&
          ids.any((id) => !normalizedKnownTodoIds.contains(id))) {
        return 'merge_todos包含当前不存在的待办ID，请先查询并使用至少两个真实待办ID';
      }
      return null;
    }
    final referenceFields = switch (actionName) {
      'update_todo' ||
      'complete_todo' ||
      'delete_todo' ||
      'reschedule_todo' ||
      'bulk_reschedule' ||
      'categorize_todo' => ['todoId', 'todo_id', 'todoUuid', 'id'],
      'split_todo' => ['sourceTodoId', 'source_id', 'todoId', 'todo_id', 'id'],
      'update_schedule' || 'cancel_schedule' || 'delete_schedule' => [
        'scheduleId',
        'schedule_id',
        'fixedScheduleId',
        'fixed_schedule_id',
        'id',
      ],
      'update_plan_block' ||
      'reschedule_plan_blocks' ||
      'delete_plan_block' ||
      'skip_plan_block' ||
      'start_plan_block_pomodoro' => [
        'planBlockId',
        'plan_block_id',
        'blockId',
        'block_id',
        'id',
      ],
      'update_time_log' || 'delete_time_log' => ['logId', 'todoId', 'id'],
      'update_countdown' || 'complete_countdown' || 'delete_countdown' => [
        'countdownId',
        'todoId',
        'id',
      ],
      'update_todo_group' || 'delete_todo_group' => [
        'groupId',
        'categoryId',
        'folderId',
        'todoId',
        'id',
      ],
      'update_pomodoro_tag' || 'delete_pomodoro_tag' => [
        'tagId',
        'todoId',
        'id',
      ],
      'update_habit' || 'delete_habit' => [
        'habitUuid',
        'habit_uuid',
        'habitId',
        'habit_id',
        'id',
      ],
      _ => null,
    };
    if (referenceFields == null) return null;
    const actionsWithTodoReferences = {
      'update_todo',
      'complete_todo',
      'delete_todo',
      'reschedule_todo',
      'bulk_reschedule',
      'categorize_todo',
      'split_todo',
    };
    final referenceDomain = switch (actionName) {
      'update_schedule' || 'cancel_schedule' || 'delete_schedule' =>
        'fixed_schedules',
      'update_plan_block' ||
      'reschedule_plan_blocks' ||
      'delete_plan_block' ||
      'skip_plan_block' ||
      'start_plan_block_pomodoro' => 'plan_blocks',
      'update_time_log' || 'delete_time_log' => 'time_logs',
      'update_countdown' || 'complete_countdown' || 'delete_countdown' =>
        'countdowns',
      'update_todo_group' || 'delete_todo_group' => 'todo_groups',
      'update_pomodoro_tag' || 'delete_pomodoro_tag' => 'pomodoro_tags',
      _ => null,
    };

    final rawRecords = action['updates'] ?? action['blocks'];
    final records = rawRecords is List
        ? rawRecords.whereType<Map>().toList(growable: false)
        : [action];
    if (records.isEmpty) return '$actionName 至少需要一条有效记录';
    for (final record in records) {
      final references = referenceFields
          .map((field) => record[field]?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();
      if (references.isEmpty) {
        return '$actionName 每项都必须携带本轮上下文中的真实对象ID';
      }
      if (references.length > 1) {
        return '$actionName每项的对象ID别名互相冲突，请只提供一个真实ID';
      }
      final reference = references.single;
      if (actionsWithTodoReferences.contains(actionName) &&
          normalizedKnownTodoIds != null &&
          !normalizedKnownTodoIds.contains(reference)) {
        return '$actionName引用了当前不存在的待办ID，请先查询并使用真实待办ID';
      }
      if ((actionName == 'update_habit' || actionName == 'delete_habit') &&
          normalizedKnownHabitIds != null &&
          !normalizedKnownHabitIds.contains(reference)) {
        return '$actionName引用了当前不存在的习惯ID，请先查询并使用真实habitUuid';
      }
      final knownDomainIds = referenceDomain == null
          ? null
          : normalizedDomainIds?[referenceDomain];
      if (knownDomainIds != null && !knownDomainIds.contains(reference)) {
        return '$actionName引用了当前不存在的对象ID，请先查询并使用真实ID';
      }
    }
    return null;
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _sameStringSet(Set<String> first, Set<String> second) =>
      first.length == second.length && first.containsAll(second);

  static int? _toPositiveInt(Object? value) {
    final parsed = _toInt(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static double? _toPositiveDouble(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
  }

  static int _createdTodoCount(String rawArguments) {
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
          count += (action['blocks'] as List).whereType<Map>().where(
            (block) =>
                block['newTodoTitle']?.toString().trim().isNotEmpty == true,
          ).length;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  static int _createdFinanceDraftCount(String rawArguments) {
    try {
      final arguments = jsonDecode(rawArguments);
      if (arguments is! Map || arguments['drafts'] is! List) return 0;
      return (arguments['drafts'] as List).whereType<Map>().length;
    } catch (_) {
      return 0;
    }
  }

  static Set<String> _cdtActionNames(String rawArguments) {
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

  static Set<String> _financeActionNames(String rawArguments) {
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

  static String _financeActionLabel(String action) => switch (action) {
    'update_finance' => '修改账单',
    'delete_finance' => '删除账单',
    _ => action,
  };

  static bool _hasNewTodoInPlan(String rawArguments) {
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

  static String _cdtActionLabel(String action) => switch (action) {
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
    'start_plan_block_pomodoro' => '启动规划番茄钟',
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
    'delete_todo' => '删除待办',
    'update_todo' => '修改待办',
    'reschedule_todo' => '改期待办',
    'categorize_todo' => '分类待办',
    'split_todo' => '拆分待办',
    'merge_todos' => '合并待办',
    _ => action,
  };

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

  static int? _explicitTodoCount(String text) =>
      AiTodoContextBuilder.explicitTodoCreationCount(text);

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

  /// Detects replies that are legitimately asking for missing write details.
  /// Shared by native and text-protocol write recovery so neither path turns a
  /// clarification into an inferred mutation.
  static bool isLikelyClarification(String content) {
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
