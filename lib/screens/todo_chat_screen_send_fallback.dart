part of 'todo_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _TodoChatSendFallback on _TodoChatScreenStateBase {
  List<String> _completeFallbackBlocks(
    String content,
    String start,
    String end,
  ) =>
      RegExp('${RegExp.escape(start)}[\\s\\S]*?${RegExp.escape(end)}')
          .allMatches(content)
          .map((match) => match.group(0)!)
          .toList();

  String _normalizeFallbackCdtActionName(Object? value) {
    final name = value?.toString() ?? '';
    return switch (name) {
      'create_habit_goal' || 'habit_create' => 'create_habit',
      'update_habit_goal' || 'habit_update' => 'update_habit',
      'delete_habit_goal' || 'habit_delete' => 'delete_habit',
      'create_fixed_schedule' => 'create_schedule',
      'update_fixed_schedule' => 'update_schedule',
      'cancel_fixed_schedule' => 'cancel_schedule',
      'delete_fixed_schedule' => 'delete_schedule',
      'bulk_reschedule' || 'bulk_reschedule_todo' => 'reschedule_todo',
      'plan_todos' ||
      'create_todo_plan_block' ||
      'schedule_todo_block' => 'create_plan_block',
      'create_group' ||
      'create_category' ||
      'create_folder' => 'create_todo_group',
      'update_group' ||
      'update_category' ||
      'update_folder' => 'update_todo_group',
      'delete_group' ||
      'delete_category' ||
      'delete_folder' => 'delete_todo_group',
      _ => name,
    };
  }

  Set<String> _fallbackCdtActionNames(String content) {
    final names = <String>{};
    for (final block in _completeFallbackBlocks(
      content,
      '[ACTION_START]',
      '[ACTION_END]',
    )) {
      try {
        final body = block
            .substring(
              '[ACTION_START]'.length,
              block.length - '[ACTION_END]'.length,
            )
            .trim();
        final decoded = jsonDecode(body);
        if (decoded is! Map || decoded['actions'] is! List) continue;
        for (final action in (decoded['actions'] as List).whereType<Map>()) {
          final name = _normalizeFallbackCdtActionName(action['action']);
          if (name.isEmpty) continue;
          names.add(name);
          final rawBlocks =
              action['blocks'] ?? action['plans'] ?? action['todos'];
          if (name == 'create_plan_block' && rawBlocks is List) {
            final createsTodo = rawBlocks.whereType<Map>().any(
              (planned) =>
                  planned['newTodoTitle']?.toString().trim().isNotEmpty == true,
            );
            if (createsTodo) names.add('create_todo');
          }
        }
      } catch (_) {
        // Malformed action blocks are surfaced by the final card check.
      }
    }
    return names;
  }

  int _fallbackCreatedTodoCount(String content) {
    var count = 0;
    for (final block in _completeFallbackBlocks(
      content,
      '[ACTION_START]',
      '[ACTION_END]',
    )) {
      try {
        final body = block
            .substring(
              '[ACTION_START]'.length,
              block.length - '[ACTION_END]'.length,
            )
            .trim();
        final decoded = jsonDecode(body);
        if (decoded is! Map || decoded['actions'] is! List) continue;
        for (final rawAction in (decoded['actions'] as List).whereType<Map>()) {
          final name = _normalizeFallbackCdtActionName(rawAction['action']);
          if (name == 'create_todo') {
            final rawTodos = rawAction['todos'];
            final todos = rawTodos is List ? rawTodos : [rawAction];
            count += todos.where((rawTodo) {
              if (rawTodo is! Map) return false;
              return rawTodo['title']?.toString().trim().isNotEmpty == true;
            }).length;
          } else if (name == 'create_plan_block') {
            final rawBlocks =
                rawAction['blocks'] ?? rawAction['plans'] ?? rawAction['todos'];
            if (rawBlocks is! List) continue;
            count += rawBlocks
                .whereType<Map>()
                .where(
                  (planned) =>
                      planned['newTodoTitle']?.toString().trim().isNotEmpty ==
                      true,
                )
                .length;
          }
        }
      } catch (_) {
        // Malformed action blocks count as no created todos.
      }
    }
    return count;
  }

  int _fallbackCreatedFinanceDraftCount(String content) =>
      FinanceTextParser.extractAssistantDrafts(content).length;

  List<String> _fallbackFinanceBlocksForMissingCount(
    String content, {
    required int? remainingDraftCount,
  }) {
    final blocks = _completeFallbackBlocks(
      content,
      '[FINANCE_START]',
      '[FINANCE_END]',
    );
    if (remainingDraftCount == null) return blocks;
    if (remainingDraftCount <= 0) return const [];

    final recovered = <String>[];
    var remaining = remainingDraftCount;
    for (final block in blocks) {
      if (remaining <= 0) break;
      try {
        final body = block
            .substring(
              '[FINANCE_START]'.length,
              block.length - '[FINANCE_END]'.length,
            )
            .trim();
        final decoded = jsonDecode(body);
        final rawDrafts = switch (decoded) {
          List value => value,
          Map value when value['drafts'] is List => value['drafts'] as List,
          Map value when value['entries'] is List => value['entries'] as List,
          Map value when value['finance'] is List => value['finance'] as List,
          Map value when value['transactions'] is List =>
            value['transactions'] as List,
          Map value => [value],
          _ => const <Object?>[],
        };
        final selectedDrafts = <Map<String, dynamic>>[];
        for (final rawDraft in rawDrafts) {
          if (rawDraft is! Map || remaining <= 0) continue;
          final draft = Map<String, dynamic>.from(rawDraft);
          final candidate =
              '[FINANCE_START]${jsonEncode([draft])}[FINANCE_END]';
          if (FinanceTextParser.extractAssistantDrafts(candidate).isEmpty) {
            continue;
          }
          selectedDrafts.add(draft);
          remaining--;
        }
        if (selectedDrafts.isNotEmpty) {
          recovered.add(
            '[FINANCE_START]\n${jsonEncode(selectedDrafts)}\n[FINANCE_END]',
          );
        }
      } catch (_) {
        // Invalid or malformed retry drafts cannot create a confirmation card.
      }
    }
    return recovered;
  }

  Set<String> _missingFallbackCdtActionNames(
    String content, {
    required Set<String> requiredFallbackCdtActionNames,
    required int? requiredFallbackTodoCount,
  }) {
    final missing = requiredFallbackCdtActionNames.difference(
      _fallbackCdtActionNames(content),
    );
    if (requiredFallbackTodoCount != null &&
        _fallbackCreatedTodoCount(content) < requiredFallbackTodoCount) {
      missing.add('create_todo');
    }
    return missing;
  }

  String _fallbackMissingCdtActionLabel(
    String name,
    String content, {
    required int? requiredFallbackTodoCount,
  }) {
    if (name != 'create_todo' || requiredFallbackTodoCount == null) {
      return cdtActionDisplayLabel(name);
    }
    final remaining =
        requiredFallbackTodoCount - _fallbackCreatedTodoCount(content);
    return remaining > 0
        ? '新建待办（还需 $remaining 条）'
        : cdtActionDisplayLabel(name);
  }

  List<String> _fallbackCdtBlocksForMissingActions(
    String content,
    Set<String> missingActions, {
    int? remainingTodoCount,
  }) {
    final blocks = _completeFallbackBlocks(
      content,
      '[ACTION_START]',
      '[ACTION_END]',
    );
    if (missingActions.isEmpty) return blocks;
    final recovered = <String>[];
    var todosRemaining = remainingTodoCount;
    for (final block in blocks) {
      try {
        final body = block
            .substring(
              '[ACTION_START]'.length,
              block.length - '[ACTION_END]'.length,
            )
            .trim();
        final decoded = jsonDecode(body);
        if (decoded is! Map || decoded['actions'] is! List) continue;
        final actions = <Map<String, dynamic>>[];
        for (final rawAction in (decoded['actions'] as List)) {
          if (rawAction is! Map) continue;
          final name = _normalizeFallbackCdtActionName(rawAction['action']);
          final action = Map<String, dynamic>.from(rawAction);
          if (name == 'create_todo' && missingActions.contains('create_todo')) {
            final rawTodos = action['todos'];
            final todos = rawTodos is List ? rawTodos : [action];
            final selectedTodos = <Object?>[];
            for (final rawTodo in todos) {
              if (rawTodo is! Map ||
                  rawTodo['title']?.toString().trim().isNotEmpty != true ||
                  (todosRemaining != null && todosRemaining <= 0)) {
                continue;
              }
              selectedTodos.add(rawTodo);
              if (todosRemaining != null) todosRemaining--;
            }
            if (selectedTodos.isEmpty) continue;
            if (rawTodos is List) action['todos'] = selectedTodos;
            actions.add(action);
            continue;
          }
          if (name == 'create_plan_block') {
            final blockField = action.containsKey('blocks')
                ? 'blocks'
                : action.containsKey('plans')
                ? 'plans'
                : action.containsKey('todos')
                ? 'todos'
                : null;
            final rawBlocks = blockField == null ? null : action[blockField];
            if (rawBlocks is List &&
                (missingActions.contains('create_plan_block') ||
                    missingActions.contains('create_todo'))) {
              final selectedBlocks = <Object?>[];
              for (final rawPlan in rawBlocks) {
                if (rawPlan is! Map) continue;
                final createsTodo =
                    rawPlan['newTodoTitle']?.toString().trim().isNotEmpty ==
                    true;
                if (createsTodo) {
                  if (todosRemaining != null && todosRemaining <= 0) {
                    continue;
                  }
                  selectedBlocks.add(rawPlan);
                  if (todosRemaining != null) todosRemaining--;
                } else if (missingActions.contains('create_plan_block')) {
                  selectedBlocks.add(rawPlan);
                }
              }
              if (selectedBlocks.isEmpty) continue;
              action[blockField!] = selectedBlocks;
              actions.add(action);
              continue;
            }
          }
          if (missingActions.contains(name)) actions.add(action);
        }
        if (actions.isEmpty) continue;
        final repairedEnvelope = Map<String, dynamic>.from(decoded)
          ..['actions'] = actions;
        recovered.add(
          '[ACTION_START]\n${jsonEncode(repairedEnvelope)}\n[ACTION_END]',
        );
      } catch (_) {
        // Ignore malformed retry blocks; they cannot create a card.
      }
    }
    return recovered;
  }

  Set<String> _missingFallbackProposalBlocks(
    String content, {
    required Set<String> allowedProposalToolNames,
    required Set<String> requiredFallbackCdtActionNames,
    required int? requiredFallbackTodoCount,
    required int? requiredFallbackFinanceDraftCount,
  }) {
    bool hasBlock(String start, String end) =>
        RegExp('${RegExp.escape(start)}[\\s\\S]*?${RegExp.escape(end)}')
            .hasMatch(content);

    return {
      if (allowedProposalToolNames.contains('propose_cdt_actions') &&
          (!hasBlock('[ACTION_START]', '[ACTION_END]') ||
              _missingFallbackCdtActionNames(
                content,
                requiredFallbackCdtActionNames: requiredFallbackCdtActionNames,
                requiredFallbackTodoCount: requiredFallbackTodoCount,
              ).isNotEmpty))
        'propose_cdt_actions',
      if (allowedProposalToolNames.contains('propose_finance_drafts') &&
          (!hasBlock('[FINANCE_START]', '[FINANCE_END]') ||
              (requiredFallbackFinanceDraftCount != null &&
                  _fallbackCreatedFinanceDraftCount(content) <
                      requiredFallbackFinanceDraftCount)))
        'propose_finance_drafts',
      if (allowedProposalToolNames.contains('propose_finance_actions') &&
          !hasBlock('[FINANCE_ACTION_START]', '[FINANCE_ACTION_END]'))
        'propose_finance_actions',
    };
  }

  String _fallbackProposalLabel(String name) => switch (name) {
    'propose_cdt_actions' => '待办、习惯、日程或规划操作卡',
    'propose_finance_drafts' => '新增账单确认卡',
    'propose_finance_actions' => '账单修改确认卡',
    _ => name,
  };

  String _fallbackMissingProposalLabel(
    String name,
    String content, {
    required int? requiredFallbackFinanceDraftCount,
  }) {
    if (name == 'propose_finance_drafts' &&
        requiredFallbackFinanceDraftCount != null) {
      final remaining =
          requiredFallbackFinanceDraftCount -
          _fallbackCreatedFinanceDraftCount(content);
      if (remaining > 0) return '新增账单确认卡（还需$remaining笔）';
    }
    return _fallbackProposalLabel(name);
  }

  String _appendFallbackBlocks(String fullContent, String blocks) {
    if (blocks.trim().isEmpty) return fullContent;
    final suggestionMatch = RegExp(r'\[SUGGEST_START\][\s\S]*?\[SUGGEST_END\]')
        .firstMatch(fullContent);
    if (suggestionMatch == null) {
      return '${fullContent.trimRight()}\n\n$blocks';
    }
    return '${fullContent.substring(0, suggestionMatch.start).trimRight()}'
        '\n\n$blocks\n\n'
        '${fullContent.substring(suggestionMatch.start)}';
  }

  @override
  Future<
    ({
      String fullContent,
      String reasoningContent,
      String latestRawModelReply,
      ChatUsageSummary? usageSummary,
    })
  >
  _retryMissingFallbackProposalBlocks({
    required String fullContent,
    required String reasoningContent,
    required String latestRawModelReply,
    required List<Map<String, dynamic>> apiMessages,
    required List<Map<String, dynamic>> fallbackWriteTools,
    required Set<String> allowedProposalToolNames,
    required Set<String> requiredFallbackCdtActionNames,
    required int? requiredFallbackTodoCount,
    required int? requiredFallbackFinanceDraftCount,
    required Stream<AiChatStreamChunk> Function(
      List<Map<String, dynamic>> messages,
      List<Map<String, dynamic>> tools, {
      String? toolChoiceName,
    })
    streamRound,
    required List<ChatUsageSummary> usageSummaries,
    required ChatUsageSummary? usageSummary,
  }) async {
    var updatedFullContent = fullContent;
    var updatedReasoningContent = reasoningContent;
    var updatedRawModelReply = latestRawModelReply;
    var updatedUsageSummary = usageSummary;

    final missingFallbackBeforeRetry = _missingFallbackProposalBlocks(
      updatedFullContent,
      allowedProposalToolNames: allowedProposalToolNames,
      requiredFallbackCdtActionNames: requiredFallbackCdtActionNames,
      requiredFallbackTodoCount: requiredFallbackTodoCount,
      requiredFallbackFinanceDraftCount: requiredFallbackFinanceDraftCount,
    );
    if (_cancelGeneration?.isCompleted != true &&
        fallbackWriteTools.isNotEmpty &&
        missingFallbackBeforeRetry.isNotEmpty &&
        !AiToolChatRunner.isLikelyClarification(updatedFullContent)) {
      final missingCdtActions = _missingFallbackCdtActionNames(
        updatedFullContent,
        requiredFallbackCdtActionNames: requiredFallbackCdtActionNames,
        requiredFallbackTodoCount: requiredFallbackTodoCount,
      );
      final existingFallbackTodoCount = _fallbackCreatedTodoCount(
        updatedFullContent,
      );
      final remainingFallbackTodoCount = requiredFallbackTodoCount == null
          ? null
          : requiredFallbackTodoCount > existingFallbackTodoCount
          ? requiredFallbackTodoCount - existingFallbackTodoCount
          : 0;
      final remainingFallbackFinanceDraftCount =
          requiredFallbackFinanceDraftCount == null
          ? null
          : (requiredFallbackFinanceDraftCount -
                    _fallbackCreatedFinanceDraftCount(updatedFullContent))
                .clamp(0, requiredFallbackFinanceDraftCount)
                .toInt();
      final missingLabels = {
        ...missingFallbackBeforeRetry.map(
          (name) => _fallbackMissingProposalLabel(
            name,
            updatedFullContent,
            requiredFallbackFinanceDraftCount:
                requiredFallbackFinanceDraftCount,
          ),
        ),
        ...missingCdtActions.map(
          (name) => _fallbackMissingCdtActionLabel(
            name,
            updatedFullContent,
            requiredFallbackTodoCount: requiredFallbackTodoCount,
          ),
        ),
      }.join('、');
      final retryMessages = [
        ...apiMessages,
        {'role': 'assistant', 'content': updatedFullContent},
        {
          'role': 'system',
          'content':
              '上一轮的操作提案缺少以下确认卡或动作：$missingLabels。应用尚未生成缺失项目的确认卡，也没有写入数据。'
              '已输出的其他操作块和确认卡会保留；请只补充缺失的操作块，不要重复已输出的块，也不要重写完整回复。'
              '${requiredFallbackTodoCount == null ? '' : '明确要求的待办数量只补足剩余条数，不能额外创建。'}'
              '${requiredFallbackFinanceDraftCount == null ? '' : '明确要求的新增账单数量只补足剩余笔数，不能重复已有账单或额外新增。'}'
              '若缺少必需信息或对象不明确，只向用户提出必要问题；不要用自然语言声称已操作或已保存。',
        },
      ];
      final retryContent = StringBuffer();
      final retryReasoning = StringBuffer();
      if (mounted) {
        _streamingContent = '';
        _streamingReasoning = '';
        _notifyStreamingBubbleChanged();
      }
      await for (final chunk in streamRound(retryMessages, const [])) {
        if (chunk.usageSummary != null) {
          usageSummaries.add(chunk.usageSummary!);
          updatedUsageSummary = ChatUsageSummary.combine(usageSummaries);
        }
        if (chunk.reasoningContent.isNotEmpty) {
          retryReasoning.write(chunk.reasoningContent);
          if (mounted) {
            _streamingReasoning = retryReasoning.toString();
            _notifyStreamingBubbleChanged();
          }
        }
        if (chunk.content.isNotEmpty) {
          retryContent.write(chunk.content);
          if (mounted) {
            _streamingContent = retryContent.toString();
            _notifyStreamingBubbleChanged();
            _scrollToBottom();
          }
        }
        if (chunk.finishReason != null && chunk.finishReason!.isNotEmpty) {
          if (mounted) _streamingFinishReason = chunk.finishReason;
        }
      }
      final retryText = retryContent.toString();
      updatedRawModelReply = retryText;
      if (retryContent.isNotEmpty) {
        final recoveredBlocks = <String>[];
        for (final name in missingFallbackBeforeRetry) {
          final (start, end) = switch (name) {
            'propose_cdt_actions' => ('[ACTION_START]', '[ACTION_END]'),
            'propose_finance_drafts' => ('[FINANCE_START]', '[FINANCE_END]'),
            'propose_finance_actions' => (
              '[FINANCE_ACTION_START]',
              '[FINANCE_ACTION_END]',
            ),
            _ => ('', ''),
          };
          if (start.isNotEmpty) {
            recoveredBlocks.addAll(switch (name) {
              'propose_cdt_actions' => _fallbackCdtBlocksForMissingActions(
                retryText,
                missingCdtActions,
                remainingTodoCount: remainingFallbackTodoCount,
              ),
              'propose_finance_drafts' => _fallbackFinanceBlocksForMissingCount(
                retryText,
                remainingDraftCount: remainingFallbackFinanceDraftCount,
              ),
              _ => _completeFallbackBlocks(retryText, start, end),
            });
          }
        }
        updatedFullContent = _appendFallbackBlocks(
          updatedFullContent,
          recoveredBlocks.join('\n\n'),
        );
        if (retryReasoning.isNotEmpty) {
          updatedReasoningContent = retryReasoning.toString();
        }
      }
    }

    return (
      fullContent: updatedFullContent,
      reasoningContent: updatedReasoningContent,
      latestRawModelReply: updatedRawModelReply,
      usageSummary: updatedUsageSummary,
    );
  }

  @override
  Future<void> _persistInterruptedAssistantReply({
    required String sessionId,
    required String requestText,
    required bool nativeToolMode,
    required String fullContent,
    required String actionContent,
    required String rawModelReply,
    required String reasoningContent,
    required ChatUsageSummary? usageSummary,
    required List<AiChatFunctionCall> nativeToolCalls,
    required Set<String> allowedCdtActionNames,
    required Set<String> allowedFinanceActionNames,
    required Set<String> allowedProposalToolNames,
    required List<String> settingsTargets,
    required Map<String, String> existingTodoTitles,
  }) async {
    if (fullContent.isNotEmpty ||
        reasoningContent.isNotEmpty ||
        nativeToolCalls.isNotEmpty ||
        _streamingToolCalls.isNotEmpty) {
      final existingScheduleTitles = {
        for (final schedule in _fixedSchedules) schedule.id: schedule.title,
      };
      final todoActions = AiActionParser.extractTodoActions(
        actionContent,
        originalText: requestText,
        existingTodoTitles: existingTodoTitles,
        existingScheduleTitles: existingScheduleTitles,
        availableTeams: _teams,
        allowedActionNames: allowedCdtActionNames,
      );
      final financeDrafts =
          allowedProposalToolNames.contains('propose_finance_drafts')
          ? FinanceTextParser.extractAssistantDrafts(actionContent)
          : <FinanceEntryDraft>[];
      final financeActions =
          FinanceTextParser.extractAssistantActions(actionContent)
              .where((action) {
                return !action.isMutation ||
                    allowedFinanceActionNames.contains(action.actionName);
              })
              .toList();
      final nativeToolCallRecords = _buildNativeToolCallRecords(
        calls: nativeToolCalls,
        todoActions: todoActions,
        financeDrafts: financeDrafts,
        financeActions: financeActions,
        interrupted: true,
      );
      final cleanContent = FinanceTextParser.cleanAssistantContent(
        AiActionParser.cleanActionContent(actionContent),
      );
      if (_memoryEnabled && !nativeToolMode) {
        unawaited(
          AiMemoryService.applyTextMemoryCommands(
            widget.username,
            actionContent,
          ).then((notices) {
            if (mounted && notices.isNotEmpty) {
              AppSnackBars.showSnackBar(
                context,
                SnackBar(content: Text(notices.join('；'))),
              );
            }
          }),
        );
      }
      final interruptedContent = _appendPendingWriteConfirmationNotice(
        content: financeDrafts.isNotEmpty
            ? _financeDraftSummary(financeDrafts.length)
            : todoActions.any((action) => action.isPlanBlockAction)
            ? _planningDraftSummary(todoActions)
            : cleanContent.isNotEmpty
            ? cleanContent
            : todoActions.isNotEmpty
            ? '已生成待确认操作草案，请核对后添加。'
            : financeActions.isNotEmpty
            ? '已生成账单操作草案，请在确认卡中核对。'
            : nativeToolCalls.isNotEmpty || _streamingToolCalls.isNotEmpty
            ? '工具调用已记录；应用没有自动修改数据。请查看调用详情和处理结果。'
            : cleanContent,
        todoActions: todoActions,
        financeDrafts: financeDrafts,
        financeActions: financeActions,
      );
      final finishReasonNote = _streamingFinishReason == null
          ? ''
          : '\n\n模型结束原因：$_streamingFinishReason；响应流收尾前已中断。';
      setState(() {
        final assistantMsg = ChatMessage(
          role: ChatRole.assistant,
          content: '$interruptedContent$finishReasonNote\n\n*(已中断)*',
          rawContent: rawModelReply,
          settingsTargets: settingsTargets,
          reasoningContent: reasoningContent,
          smartContext: _lastRequestSmartContext,
          usageSummary: usageSummary,
          todoActions: todoActions.isNotEmpty ? todoActions : null,
          financeDrafts: financeDrafts.isNotEmpty ? financeDrafts : null,
          financeActions: financeActions.isNotEmpty ? financeActions : null,
          nativeToolCalls: nativeToolCallRecords.isNotEmpty
              ? nativeToolCallRecords
              : null,
        );
        _messages.add(assistantMsg);
        _streamingContent = '';
        _streamingReasoning = '';
        _streamingToolCalls = [];
        _streamingFinishReason = null;
        _isLoading = false;
        _cancelGeneration = null;
        ChatStorageService.addMessage(assistantMsg, sessionId: sessionId);
      });
    } else {
      setState(() {
        _streamingContent = '';
        _streamingReasoning = '';
        _streamingToolCalls = [];
        _streamingFinishReason = null;
        _isLoading = false;
        _cancelGeneration = null;
      });
    }
    _scrollToBottom();
    return;
  }

  @override
  Future<void> _finalizeStreamedAssistantReply({
    required String sessionId,
    required String requestText,
    required bool nativeToolMode,
    required bool hasRequestedCountdownTeamBinding,
    required Team? requestedCountdownTeam,
    required String? requestedCountdownTeamName,
    required List<Map<String, dynamic>> fallbackWriteTools,
    required String fullContent,
    required String actionContent,
    required String rawModelReply,
    required String reasoningContent,
    required ChatUsageSummary? usageSummary,
    required List<AiChatFunctionCall> nativeToolCalls,
    required Set<String> allowedCdtActionNames,
    required Set<String> allowedFinanceActionNames,
    required Set<String> allowedProposalToolNames,
    required Set<String> requiredFallbackCdtActionNames,
    required int? requiredFallbackTodoCount,
    required int? requiredFallbackFinanceDraftCount,
    required List<String> settingsTargets,
    required Map<String, String> existingTodoTitles,
  }) async {
    if (actionContent.isEmpty &&
        reasoningContent.isEmpty &&
        nativeToolCalls.isEmpty) {
      throw Exception('未收到有效回复');
    }

    final existingScheduleTitles = {
      for (final schedule in _fixedSchedules) schedule.id: schedule.title,
    };
    final parsedTodoActions = AiActionParser.extractTodoActions(
      actionContent,
      originalText: requestText,
      existingTodoTitles: existingTodoTitles,
      existingScheduleTitles: existingScheduleTitles,
      availableTeams: _teams,
      allowedActionNames: allowedCdtActionNames,
    );
    final hasUnresolvedCountdownTeamBinding =
        (hasRequestedCountdownTeamBinding && requestedCountdownTeam == null) ||
        parsedTodoActions.any(_hasUnresolvedCountdownTeamBinding);
    final todoActions = hasUnresolvedCountdownTeamBinding
        ? parsedTodoActions
              .where(
                (action) => action.type != AiTodoActionType.createCountdown,
              )
              .toList(growable: false)
        : parsedTodoActions;
    final financeDrafts =
        allowedProposalToolNames.contains('propose_finance_drafts')
        ? FinanceTextParser.extractAssistantDrafts(actionContent)
        : <FinanceEntryDraft>[];
    final financeActions =
        FinanceTextParser.extractAssistantActions(actionContent)
            .where((action) {
              return !action.isMutation ||
                  allowedFinanceActionNames.contains(action.actionName);
            })
            .toList();
    final nativeToolCallRecords = _buildNativeToolCallRecords(
      calls: nativeToolCalls,
      todoActions: todoActions,
      financeDrafts: financeDrafts,
      financeActions: financeActions,
    );
    final inlineSuggestions = _extractFreshSuggestions(
      actionContent,
      todoActions: todoActions,
      financeDrafts: financeDrafts,
      financeActions: financeActions,
      settingsTargets: settingsTargets,
      nativeToolCalls: nativeToolCallRecords,
    );
    final cleanContent = FinanceTextParser.cleanAssistantContent(
      AiActionParser.cleanActionContent(actionContent),
    );
    if (_memoryEnabled && !nativeToolMode) {
      unawaited(
        AiMemoryService.applyTextMemoryCommands(
          widget.username,
          actionContent,
        ).then((notices) {
          if (mounted && notices.isNotEmpty) {
            AppSnackBars.showSnackBar(
              context,
              SnackBar(content: Text(notices.join('；'))),
            );
          }
        }),
      );
    }
    final parsedFallbackCdtActionNames = nativeToolMode
        ? const <String>{}
        : _parsedCdtActionNames(todoActions);
    final missingParsedFallbackCdtActions = nativeToolMode
        ? const <String>{}
        : requiredFallbackCdtActionNames.difference(
            parsedFallbackCdtActionNames,
          );
    final missingFallbackCdtActions = nativeToolMode
        ? const <String>{}
        : {
            ...missingParsedFallbackCdtActions,
            ..._missingFallbackCdtActionNames(
              fullContent,
              requiredFallbackCdtActionNames: requiredFallbackCdtActionNames,
              requiredFallbackTodoCount: requiredFallbackTodoCount,
            ),
          };
    final missingFallbackWrites = !nativeToolMode
        ? {
            ..._missingFallbackProposalBlocks(
              fullContent,
              allowedProposalToolNames: allowedProposalToolNames,
              requiredFallbackCdtActionNames: requiredFallbackCdtActionNames,
              requiredFallbackTodoCount: requiredFallbackTodoCount,
              requiredFallbackFinanceDraftCount:
                  requiredFallbackFinanceDraftCount,
            ),
            if (missingFallbackCdtActions.isNotEmpty) 'propose_cdt_actions',
          }
        : const <String>{};
    final hasAnyFallbackWriteCard =
        todoActions.isNotEmpty ||
        financeDrafts.isNotEmpty ||
        financeActions.any((action) => action.isMutation);
    final nativeWriteProposalUnresolved =
        nativeToolMode &&
        nativeToolCalls.any(
          (call) => const {
            'propose_cdt_actions',
            'propose_finance_drafts',
            'propose_finance_actions',
          }.contains(call.name),
        ) &&
        !hasAnyFallbackWriteCard &&
        !AiToolChatRunner.isLikelyClarification(cleanContent);
    final fallbackWriteIncomplete =
        !nativeToolMode &&
        fallbackWriteTools.isNotEmpty &&
        (missingFallbackWrites.isNotEmpty || !hasAnyFallbackWriteCard) &&
        !AiToolChatRunner.isLikelyClarification(cleanContent);
    final fallbackWriteWarning = !fallbackWriteIncomplete
        ? null
        : hasAnyFallbackWriteCard
        ? '已生成部分待确认操作卡，但还缺少${[for (final name in missingFallbackWrites)
            if (name != 'propose_cdt_actions' || missingFallbackCdtActions.isEmpty) _fallbackMissingProposalLabel(name, fullContent, requiredFallbackFinanceDraftCount: requiredFallbackFinanceDraftCount), ...missingFallbackCdtActions.map((name) => _fallbackMissingCdtActionLabel(name, fullContent, requiredFallbackTodoCount: requiredFallbackTodoCount))].join('、')}；应用没有写入缺失操作，请核对现有卡片并重试。'
        : '本轮未生成有效的待确认操作卡，应用没有写入数据。请补充信息或重试。';
    final String? unresolvedCountdownTeamReply;
    if (hasUnresolvedCountdownTeamBinding &&
        hasRequestedCountdownTeamBinding &&
        requestedCountdownTeam == null) {
      unresolvedCountdownTeamReply =
          '本地团队列表中没有找到唯一匹配的团队「${requestedCountdownTeamName ?? '本轮指定团队'}」，未生成团队绑定的倒计时草案。请核对名称后重试。';
    } else if (hasUnresolvedCountdownTeamBinding) {
      unresolvedCountdownTeamReply =
          '返回的团队无法匹配本地团队列表，相关倒计时草案未生成。请从本地团队中选择准确团队后重试。';
    } else {
      unresolvedCountdownTeamReply = null;
    }
    final assistantContent = _appendPendingWriteConfirmationNotice(
      content:
          unresolvedCountdownTeamReply ??
          fallbackWriteWarning ??
          (nativeWriteProposalUnresolved
              ? '模型函数调用未能解析成有效操作卡，本地数据没有更改。请补充具体对象或信息后重试。'
              : null) ??
          (financeDrafts.isNotEmpty
              ? _financeDraftSummary(financeDrafts.length)
              : todoActions.any((action) => action.isPlanBlockAction)
              ? _planningDraftSummary(todoActions)
              : allowedCdtActionNames.contains('create_plan_block') &&
                    nativeToolCalls.any(
                      (call) => call.name == 'propose_cdt_actions',
                    ) &&
                    todoActions.isEmpty
              ? '规划工具返回的草案未通过校验，没有生成可执行卡片，也未保存任何数据。请重新生成规划。'
              : cleanContent.isNotEmpty
              ? cleanContent
              : todoActions.isNotEmpty
              ? '已生成待确认操作草案，请核对后添加。'
              : financeActions.isNotEmpty
              ? '已生成账单操作草案，请在确认卡中核对。'
              : settingsTargets.isNotEmpty
              ? '已找到相关设置，点击卡片即可前往调整。'
              : nativeToolCalls.isNotEmpty
              ? '本轮已完成 ${nativeToolCalls.length} 次工具调用，但模型未返回总结正文${_streamingFinishReason != null ? '（finish_reason=$_streamingFinishReason）' : ''}。可点击重试或继续追问；若因单轮预算触发上限，可在 AI 助手设置中调高预算。'
              : cleanContent),
      todoActions: todoActions,
      financeDrafts: financeDrafts,
      financeActions: financeActions,
    );

    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: assistantContent,
      rawContent: rawModelReply,
      settingsTargets: settingsTargets,
      reasoningContent: reasoningContent,
      smartContext: _lastRequestSmartContext,
      usageSummary: usageSummary,
      todoActions: todoActions.isNotEmpty ? todoActions : null,
      financeDrafts: financeDrafts.isNotEmpty ? financeDrafts : null,
      financeActions: financeActions.isNotEmpty ? financeActions : null,
      nativeToolCalls: nativeToolCallRecords.isNotEmpty
          ? nativeToolCallRecords
          : null,
    );
    var supersededDraftsIgnored = false;
    setState(() {
      _messages.add(assistantMsg);
      if (financeDrafts.length == 1) {
        supersededDraftsIgnored = _ignoreSupersededDateCorrectionDrafts(
          assistantMsg,
          financeDrafts.single,
        );
      }
      _streamingContent = '';
      _streamingReasoning = '';
      _streamingToolCalls = [];
      _streamingFinishReason = null;
      _isLoading = false;
      _cancelGeneration = null;
      _suggestions = inlineSuggestions;
      if (todoActions.isNotEmpty) {
        _actionRailCollapsed = false;
      }
    });
    await ChatStorageService.addMessage(assistantMsg, sessionId: sessionId);
    if (supersededDraftsIgnored) await _saveHistorySilently();
    _scrollToBottom();
    _generateSessionTitle(sessionId: sessionId);
  }

  @override
  Future<void> _handleSendMessageError({
    required Object error,
    required String sessionId,
    required bool useQueryTools,
    required ChatUsageSummary? usageSummary,
  }) async {
    if (mounted) {
      final partialToolCalls = _streamingToolCalls
          .map(
            (call) => ChatNativeToolCall(
              id: call.id,
              name: call.name,
              arguments: call.arguments,
              result: _queryToolResults[call.id],
              resultSummary: _queryToolResults.containsKey(call.id)
                  ? '${_queryResultSummary(_queryToolResults[call.id])} 后续生成中断。'
                  : call.argumentsComplete
                  ? '请求中断，工具参数已收全但草案未完成处理；本地数据未修改。'
                  : '请求中断，参数可能不完整；本地数据未修改。',
              argumentsComplete: call.argumentsComplete,
            ),
          )
          .toList(growable: false);
      final finishReason = _streamingFinishReason;
      final hasPartialReply =
          _streamingContent.isNotEmpty || _streamingReasoning.isNotEmpty;
      final diagnosticMessage =
          partialToolCalls.isEmpty && !hasPartialReply && finishReason == null
          ? null
          : ChatMessage(
              role: ChatRole.assistant,
              content: useQueryTools && partialToolCalls.isNotEmpty
                  ? '工具查询过程中断（已执行 ${partialToolCalls.length} 次调用，原因：$error）；已返回的数据保留在调用记录中。'
                  : finishReason != null
                  ? '模型已结束本轮内容（finish_reason=$finishReason），但未收到有效回复（$error）；未修改本地数据。'
                  : '请求中断（$error）；应用记录了已收到的部分内容，未修改本地数据。',
              rawContent: _streamingContent,
              reasoningContent: _streamingReasoning,
              smartContext: _lastRequestSmartContext,
              usageSummary: usageSummary,
              nativeToolCalls: partialToolCalls.isNotEmpty
                  ? partialToolCalls
                  : null,
            );
      setState(() {
        if (diagnosticMessage != null) _messages.add(diagnosticMessage);
        _streamingContent = '';
        _streamingReasoning = '';
        _streamingToolCalls = [];
        _streamingFinishReason = null;
        _isLoading = false;
        _cancelGeneration = null;
      });
      if (diagnosticMessage != null) {
        try {
          await ChatStorageService.addMessage(
            diagnosticMessage,
            sessionId: sessionId,
          );
        } catch (_) {
          // Keep the visible diagnostic even if history storage is busy.
        }
      }
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('AI回复失败: $error')),
      );
    }
  }
}
