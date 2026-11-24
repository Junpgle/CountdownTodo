part of '../ai_tool_chat_runner.dart';

Stream<AiChatStreamChunk> _runAiToolChat({
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
  int? maxQueryRounds = 4,
  int? maxCalls = 8,
  int? maxTurnChars = AiToolResultContext.maxTurnChars,
  Future<Map<String, dynamic>> Function(Map<String, dynamic> arguments)?
  onManageMemory,
}) async* {
  final effectiveMaxTurnChars = maxTurnChars == null
      ? null
      : (maxTurnChars < 400 ? 400 : maxTurnChars);
  final history = _initialHistory(
    messages,
    compactForPlanning:
        requirePlanningProposal &&
        _isSelfContainedPlanningRequest(planningRequestText),
  );
  var callCount = 0;
  var toolCallIndexOffset = 0;
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
        .map(
          (name) => switch (name) {
            'propose_cdt_actions' => '待办/日程/习惯操作',
            'propose_finance_drafts' => '记账草案',
            'propose_finance_actions' => '账单修改草案',
            _ => name,
          },
        )
        .join('、');
    return '已生成部分待确认操作卡，但模型未能补齐：$labels。现有卡片尚未写入，请核对后再补充缺少的操作。';
  }

  for (
    var round = 0;
    maxQueryRounds == null || round <= maxQueryRounds + 1;
    round++
  ) {
    if (cancelled()) return;
    final finalRound =
        (maxQueryRounds != null && round >= maxQueryRounds) ||
        (maxCalls != null && callCount >= maxCalls) ||
        (effectiveMaxTurnChars != null &&
            resultChars > effectiveMaxTurnChars - 400);
    final unsubmittedWriteProposalNames = requiredWriteProposalNames.difference(
      completedWriteProposalNames,
    );
    final roundTools = tools.where((tool) {
      final name = (tool['function'] as Map)['name'] as String;
      final isQuery = AiQueryToolService.toolNames.contains(name);
      final isUnsubmittedWriteProposal = unsubmittedWriteProposalNames.contains(
        name,
      );
      return (!finalRound || !isQuery) &&
          (!proposalsProduced || isQuery || isUnsubmittedWriteProposal) &&
          (!planningRepairAttempted || isUnsubmittedWriteProposal) &&
          (!planningScheduleRepairAttempted || isUnsubmittedWriteProposal) &&
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
        // Query-only turns can expose the incremental call stream for the
        // thinking UI. When a write proposal is available, wait until the
        // complete call has passed app-side validation before emitting it.
        toolCallDeltas: hasWriteProposalTool
            ? const []
            : [
                for (final delta in chunk.toolCallDeltas)
                  AiChatFunctionCallDelta(
                    index: delta.index + toolCallIndexOffset,
                    id: delta.id,
                    name: delta.name,
                    arguments: delta.arguments,
                  ),
              ],
        // Emit calls only after the complete proposal passes app-side
        // validation. Malformed writes must not reach the action parser.
        finishReason: chunk.finishReason,
        usage: chunk.usage,
        usageSummary: chunk.usageSummary,
      );
    }
    if (!hasWriteProposalTool) toolCallIndexOffset += calls.length;
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
        legacyCalls.hadToolMarkup && legacyCalls.calls.isEmpty && calls.isEmpty;
    if (unsupportedLegacyToolMarkup) {
      if (hasPlanningTool || hasWriteProposalTool) {
        if (content.trim().isEmpty) {
          content = '上一轮返回了当前未开放的文本工具调用。';
        }
      } else if (legacyCalls.hadDisallowedWriteMarkup) {
        if (content.trim().isEmpty) {
          content = '上一轮返回了当前未开放的写入建议；如需生成待办或日程确认卡，请明确说明“帮我创建/添加”。';
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
            pendingReferenceDomains.addAll(_queryReferenceDomains(readCall));
          }
        }
        final dependencyIssue =
            '本轮同时发起了只读查询和依赖现有对象的写入提案。查询结果尚未返回，'
            'App没有生成此提案的确认卡；请先使用查询结果中的真实ID，再单独提交写入提案。';
        issue = issue == null ? dependencyIssue : '$issue；$dependencyIssue';
      }
      final validationIssue = issue;
      if (validationIssue != null) {
        proposalValidationIssues.putIfAbsent(call.id, () => validationIssue);
      } else if (call.name == 'propose_cdt_actions') {
        createdTodoCount += _createdTodoCount(call.arguments);
        createdTodoRemarkCount += _createdTodoRemarkCount(call.arguments);
      } else if (call.name == 'propose_finance_drafts') {
        createdFinanceDraftCount += _createdFinanceDraftCount(call.arguments);
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
      final issue = '用户明确要求 $requestedTodoCount 条待办，当前提案只有 $createdTodoCount 条';
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
      final missingCdtActionNames = requiredCdtActionNames.difference(
        proposedCdtActionNames,
      );
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
        proposedFinanceActionNames.addAll(_financeActionNames(call.arguments));
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
      if (_isLikelyClarification(content) && !unsupportedLegacyToolMarkup) {
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
      if (_isLikelyClarification(content) && !unsupportedLegacyToolMarkup) {
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
      if (_isLikelyClarification(content)) {
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
          content: '[SUGGEST_START]${jsonEncode(suggestions)}[SUGGEST_END]',
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
      final isMemoryTool = call.name == AiMemoryService.toolName;
      if (!isMemoryTool) {
        callCount++;
      }
      final requiredProposalNotYetSubmitted =
          requiredWriteProposalNames.contains(call.name) &&
          !completedWriteProposalNames.contains(call.name);
      Map<String, dynamic> result;
      if (!roundAllowedToolNames.contains(call.name)) {
        result = {'ok': false, 'error': '本轮未开放此工具'};
      } else if (!usedIds.add(call.id)) {
        result = {'ok': false, 'error': '重复的工具调用ID，未再次执行'};
      } else if (maxCalls != null &&
          callCount > maxCalls &&
          !requiredProposalNotYetSubmitted &&
          !isMemoryTool) {
        result = {'ok': false, 'error': '本轮工具调用次数达到上限'};
      } else if (AiQueryToolService.toolNames.contains(call.name) &&
          effectiveMaxTurnChars != null &&
          resultChars > effectiveMaxTurnChars - 400) {
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
      } else if (call.name == AiMemoryService.toolName) {
        if (onManageMemory == null) {
          result = {'ok': false, 'message': '当前会话未启用 AI 记忆写入。'};
        } else {
          try {
            final decoded = jsonDecode(call.arguments);
            if (decoded is Map) {
              result = await onManageMemory(Map<String, dynamic>.from(decoded));
            } else {
              result = {'ok': false, 'message': 'AI 记忆工具参数格式无效。'};
            }
          } catch (_) {
            result = {'ok': false, 'message': 'AI 记忆工具参数解析失败。'};
          }
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
              validatedFinanceCatalogIdsByKind
                  .putIfAbsent(entry.key, () => <String>{})
                  .addAll(entry.value);
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
      final maxResultChars = effectiveMaxTurnChars == null
          ? AiToolResultContext.maxResultChars
          : (effectiveMaxTurnChars - resultChars).clamp(
              400,
              AiToolResultContext.maxResultChars,
            );
      final modelResult = AiToolResultContext.forModel(
        modelSource,
        maxChars: maxResultChars,
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
      if ((actionProposalRepairAttempted && !canRetryWithReadyReferences) ||
          (maxQueryRounds != null && round >= maxQueryRounds + 1)) {
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
            '${deferredReferenceProposal && allDependencyQueriesSucceeded
                ? '查询结果已返回；现在只根据结果中的真实ID重新调用对应提案工具，不要再次查询。'
                : deferredReferenceProposal
                ? '相关查询结果有失败或不完整；不要猜测对象ID，先重试查询或向用户追问。'
                : validWriteProposalNames.isEmpty
                ? '现在请修正参数并重新调用对应提案工具。'
                : '其他有效提案已保留；不要重复它们，只补齐无效调用对应的提案。'}'
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

List<Map<String, dynamic>> _initialHistory(
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

List<Map<String, dynamic>> _decodeCdtProposalActions(
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
