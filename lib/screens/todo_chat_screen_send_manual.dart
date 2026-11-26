part of 'todo_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _TodoChatSendManual on _TodoChatScreenStateBase {
  Future<void> _copyManualPromptFromInput() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    // An external model cannot call the app's read-only query tools, so the
    // copied request must carry its data through smart context injection.
    final useContextInjection = _smartContext;
    final financeContext = useContextInjection
        ? await FinanceAiContextService.buildContext(
            userMessage: text,
            conversationContext: _recentConversationTextForContext(),
            previousUserMessage: _latestUserTextFromHistory(),
            dateRangeOverride: _financeContextDateRangeOverride(),
          )
        : '';
    final habitContext = useContextInjection
        ? await HabitAiContextService.buildContext(
            userMessage: text,
            conversationContext: _recentConversationTextForContext(),
            previousUserMessage: _latestUserTextFromHistory(),
            goals: _habitGoals,
          )
        : null;
    final apiMessages = _buildApiMessages(
      pendingUserText: text,
      financeContext: financeContext,
      habitContext: habitContext ?? '',
      contextInjection: useContextInjection,
      queryTools: false,
    );
    final manualPrompt = AiTodoContextBuilder.buildManualCopyPrompt(
      apiMessages,
    );
    _pendingManualOriginalText = text;
    _pendingManualSmartContext = _lastRequestSmartContext;
    await Clipboard.setData(ClipboardData(text: manualPrompt));
    if (!mounted) return;
    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: Text(
          useContextInjection
              ? '已按智能注入模式复制提示词，可粘贴到外部AI'
              : '已复制提示词；智能上下文当前关闭，未附带业务数据',
        ),
      ),
    );
  }

  Future<void> _pasteManualReplyFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final replyCtrl = TextEditingController(text: data?.text?.trim() ?? '');

    final reply = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴AI回复并识别'),
        content: SizedBox(
          width: MediaQuery.sizeOf(ctx).width * 0.86,
          child: TextField(
            controller: replyCtrl,
            maxLines: 12,
            minLines: 6,
            decoration: const InputDecoration(
              hintText: '粘贴外部AI返回的完整内容，包含正文和 ACTION 操作块',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, replyCtrl.text),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: const Text('识别'),
          ),
        ],
      ),
    );
    replyCtrl.dispose();

    if (reply == null || reply.trim().isEmpty) return;
    await _importManualAiReply(reply.trim());
  }

  Future<void> _importManualAiReply(String fullContent) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    final originalText = _pendingManualOriginalText.isNotEmpty
        ? _pendingManualOriginalText
        : (_inputCtrl.text.trim().isNotEmpty
              ? _inputCtrl.text.trim()
              : _lastUserContent());
    final smartContext = _pendingManualSmartContext;
    final previousUserMessage = _latestUserTextFromHistory();
    final previousAssistantMessage = _latestAssistantMessageForActionRouting();
    final manualProposalToolDefinitions =
        AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          originalText,
          previousUserMessage: previousUserMessage,
          previousAssistantMessage: previousAssistantMessage,
          availableTeams: _teams,
        );
    final allowedManualCdtActions =
        AiNativeToolDefinitionBuilder.allowedCdtActionNames(
          manualProposalToolDefinitions,
        );
    final allowedManualFinanceActions =
        AiNativeToolDefinitionBuilder.allowedFinanceActionNames(
          manualProposalToolDefinitions,
        );
    final allowedManualProposalToolNames =
        AiNativeToolDefinitionBuilder.allowedToolNames(
          manualProposalToolDefinitions,
        );
    final existingTodoTitles = await _existingTodoTitleMap(
      allowedManualCdtActions,
    );
    final existingScheduleTitles = {
      for (final schedule in _fixedSchedules) schedule.id: schedule.title,
    };
    final todoActions = AiActionParser.extractTodoActions(
      fullContent,
      originalText: originalText,
      existingTodoTitles: existingTodoTitles,
      existingScheduleTitles: existingScheduleTitles,
      availableTeams: _teams,
      allowedActionNames: allowedManualCdtActions,
    );
    final settingsTargets =
        AiSettingsNavigationService.shouldOfferForRequest(originalText)
        ? AiSettingsNavigationService.extractTargets(fullContent)
        : const <String>[];
    final financeDrafts =
        allowedManualProposalToolNames.contains('propose_finance_drafts')
        ? FinanceTextParser.extractAssistantDrafts(fullContent)
        : <FinanceEntryDraft>[];
    final financeActions =
        FinanceTextParser.extractAssistantActions(fullContent).where((action) {
          return !action.isMutation ||
              allowedManualFinanceActions.contains(action.actionName);
        }).toList();
    final inlineSuggestions = _extractFreshSuggestions(
      fullContent,
      todoActions: todoActions,
      financeDrafts: financeDrafts,
      financeActions: financeActions,
      settingsTargets: settingsTargets,
      nativeToolCalls: const [],
    );
    final cleanContent = FinanceTextParser.cleanAssistantContent(
      AiActionParser.cleanActionContent(fullContent),
    );
    final requiredManualCdtActions =
        AiTodoContextBuilder.requiredExplicitCdtActionNames(
          originalText,
          previousUserMessage: previousUserMessage,
          previousAssistantMessage: previousAssistantMessage,
        );
    final missingManualCdtActions = requiredManualCdtActions.difference(
      _parsedCdtActionNames(todoActions),
    );
    final missingManualFinanceActions = allowedManualFinanceActions.difference(
      financeActions
          .where((action) => action.isMutation)
          .map((action) => action.actionName)
          .toSet(),
    );
    final requiredManualTodoCount =
        allowedManualCdtActions.contains('create_todo')
        ? AiTodoContextBuilder.explicitTodoCreationCount(originalText)
        : null;
    final missingManualTodoCount = requiredManualTodoCount == null
        ? 0
        : (requiredManualTodoCount - _parsedTodoCreationCount(todoActions))
              .clamp(0, requiredManualTodoCount)
              .toInt();
    final requiredManualFinanceDraftCount =
        allowedManualProposalToolNames.contains('propose_finance_drafts')
        ? AiTodoContextBuilder.explicitFinanceDraftCount(originalText)
        : null;
    final missingManualFinanceDraftCount =
        requiredManualFinanceDraftCount == null
        ? 0
        : (requiredManualFinanceDraftCount - financeDrafts.length)
              .clamp(0, requiredManualFinanceDraftCount)
              .toInt();
    final missingManualProposalLabels = <String>{
      if (missingManualTodoCount > 0) '还缺少 $missingManualTodoCount 条待办',
      ...missingManualCdtActions
          .where(
            (name) => name != 'create_todo' || requiredManualTodoCount == null,
          )
          .map(cdtActionDisplayLabel),
      ...missingManualFinanceActions.map(
        (name) => switch (name) {
          'update_finance' => '修改账单操作',
          'delete_finance' => '删除账单操作',
          _ => name,
        },
      ),
      if (requiredManualFinanceDraftCount == null &&
          allowedManualProposalToolNames.contains('propose_finance_drafts') &&
          AiTodoContextBuilder.shouldOfferFinanceDraftProposal(originalText) &&
          financeDrafts.isEmpty)
        '新增账单确认卡',
      if (missingManualFinanceDraftCount > 0)
        '还缺少 $missingManualFinanceDraftCount 笔账单',
    };
    final incompleteManualProposalNotice =
        missingManualProposalLabels.isNotEmpty &&
            !AiToolChatRunner.isLikelyClarification(cleanContent)
        ? '外部AI回复缺少${missingManualProposalLabels.join('、')}；本次只识别到已生成的部分草案，没有写入数据。请补齐提案后重新粘贴。'
        : null;
    final manualAssistantContent =
        incompleteManualProposalNotice ??
        (financeDrafts.isNotEmpty
            ? _financeDraftSummary(financeDrafts.length)
            : cleanContent.isEmpty
            ? settingsTargets.isNotEmpty
                  ? '已找到相关设置，点击卡片即可前往调整。'
                  : financeActions.isNotEmpty
                  ? '已生成账单操作草案，请在确认卡中核对。'
                  : fullContent
            : cleanContent);

    final newMessages = <ChatMessage>[];
    if (originalText.isNotEmpty && _lastUserContent() != originalText) {
      newMessages.add(ChatMessage(role: ChatRole.user, content: originalText));
    }
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: _appendPendingWriteConfirmationNotice(
        content: manualAssistantContent,
        todoActions: todoActions,
        financeDrafts: financeDrafts,
        financeActions: financeActions,
      ),
      rawContent: fullContent,
      settingsTargets: settingsTargets,
      smartContext: smartContext,
      todoActions: todoActions.isNotEmpty ? todoActions : null,
      financeDrafts: financeDrafts.isNotEmpty ? financeDrafts : null,
      financeActions: financeActions.isNotEmpty ? financeActions : null,
    );
    newMessages.add(assistantMsg);

    var supersededDraftsIgnored = false;
    setState(() {
      _messages.addAll(newMessages);
      _ensureActiveSessionInList();
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
      if (_inputCtrl.text.trim() == originalText) {
        _inputCtrl.clear();
      }
      _pendingManualOriginalText = '';
      _pendingManualSmartContext = '';
    });
    for (final message in newMessages) {
      await ChatStorageService.addMessage(message, sessionId: sessionId);
    }
    if (supersededDraftsIgnored) await _saveHistorySilently();
    _scrollToBottom();
    _generateSessionTitle(sessionId: sessionId);
  }

  Future<Map<String, String>> _existingTodoTitleMap(
    Set<String> allowedActionNames,
  ) async {
    const actionsRequiringCurrentTodoIds = {
      'update_todo',
      'complete_todo',
      'skip_todo',
      'delete_todo',
      'reschedule_todo',
      'bulk_reschedule',
      'categorize_todo',
      'split_todo',
      'merge_todos',
      'create_plan_block',
      'start_pomodoro',
    };
    final titles = <String, String>{
      for (final todo in widget.todos)
        if (todo['id'] != null) todo['id'].toString(): '${todo['title'] ?? ''}',
    };
    if (!allowedActionNames.any(actionsRequiringCurrentTodoIds.contains)) {
      return titles;
    }

    // The screen may receive only pending todos (for example from the home
    // dashboard), while a query tool can return completed todos too. Build the
    // resolver from local storage so valid queried IDs still reach a card.
    final currentTodos = await StorageService.getTodos(widget.username);
    for (final todo in currentTodos) {
      titles.putIfAbsent(todo.id, () => todo.title);
    }
    return titles;
  }

  Future<Map<String, Set<String>>> _loadKnownReferenceIdsByDomain(
    Set<String> allowedActionNames,
  ) async {
    final referenceActionsByDomain = <String, Set<String>>{
      'fixed_schedules': {
        'update_schedule',
        'cancel_schedule',
        'delete_schedule',
      },
      'plan_blocks': {
        'update_plan_block',
        'reschedule_plan_blocks',
        'delete_plan_block',
        'skip_plan_block',
        'start_plan_block_pomodoro',
      },
      'time_logs': {'update_time_log', 'delete_time_log'},
      'countdowns': {
        'update_countdown',
        'complete_countdown',
        'delete_countdown',
      },
      'todo_groups': {
        'update_todo_group',
        'delete_todo_group',
        'create_todo',
        'update_todo',
        'categorize_todo',
      },
      'pomodoro_tags': {
        'update_pomodoro_tag',
        'delete_pomodoro_tag',
        'create_time_log',
        'create_habit',
        'update_time_log',
        'start_pomodoro',
      },
      'recurring_todo_series': {'create_habit'},
    };
    final result = <String, Set<String>>{};
    for (final entry in referenceActionsByDomain.entries) {
      if (!allowedActionNames.any(entry.value.contains)) continue;
      final ids = switch (entry.key) {
        'fixed_schedules' => (await StorageService.getFixedSchedules(
          widget.username,
        )).map((item) => item.id),
        'plan_blocks' => (await StorageService.getPlanBlocks(
          widget.username,
        )).map((item) => item.id),
        'time_logs' => (await StorageService.getTimeLogs(
          widget.username,
        )).map((item) => item.id),
        'countdowns' => (await StorageService.getCountdowns(
          widget.username,
        )).map((item) => item.id),
        'todo_groups' => (await StorageService.getTodoGroups(
          widget.username,
        )).map((item) => item.id),
        'pomodoro_tags' => (await PomodoroService.getTags()).map(
          (item) => item.uuid,
        ),
        'recurring_todo_series' =>
          (await StorageService.getTodos(widget.username))
              .where(
                (todo) =>
                    !todo.isDeleted && todo.recurrence != RecurrenceType.none,
              )
              .map(
                (todo) => todo.recurrenceSeriesId?.trim().isNotEmpty == true
                    ? todo.recurrenceSeriesId!.trim()
                    : todo.id,
              ),
        _ => const <String>[],
      };
      result[entry.key] = ids.where((id) => id.trim().isNotEmpty).toSet();
    }
    return result;
  }

  String _lastUserContent() {
    for (final message in _messages.reversed) {
      if (message.role == ChatRole.user) return message.content;
    }
    return '';
  }

  void _stopGeneration() {
    if (_cancelGeneration != null && !_cancelGeneration!.isCompleted) {
      _cancelGeneration!.complete();
    }
  }

  void _retryLastMessage() {
    // 找到最后一条用户消息
    final lastUserMsg = _messages.lastWhere(
      (m) => m.role == ChatRole.user,
      orElse: () => ChatMessage(role: ChatRole.user, content: ''),
    );
    if (lastUserMsg.content.isEmpty && lastUserMsg.attachment == null) return;
    // 删除最后一条助手消息（如果有）
    if (_messages.isNotEmpty && _messages.last.role == ChatRole.assistant) {
      _messages.removeLast();
    }
    _inputCtrl.text = lastUserMsg.content;
    _pendingAttachment = lastUserMsg.attachment;
    _sendMessage();
  }

  Future<void> _syncSessionsFromStorage() async {
    final sessions = await ChatStorageService.loadSessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
    });
  }

  Future<void> _generateSessionTitle({required String sessionId}) async {
    final session = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => ChatSession(title: '新对话'),
    );
    if (session.title != '新对话') return;

    try {
      String model = _chatModel;
      String apiKey = _chatApiKey;
      String apiUrl = _chatApiUrl;
      String provider = _chatProvider;

      if (model.isEmpty || apiKey.isEmpty) {
        final globalConfig = await LLMService.getConfig();
        if (globalConfig != null && globalConfig.isConfigured) {
          model = globalConfig.model;
          apiKey = globalConfig.apiKey;
          apiUrl = globalConfig.apiUrl;
          provider = globalConfig.provider;
        } else {
          await _syncSessionsFromStorage();
          return;
        }
      }

      if (apiUrl.isEmpty) apiUrl = AiChatService.defaultApiUrl;

      final history = await ChatStorageService.loadHistory(sessionId);
      if (history.isEmpty) return;
      final firstUserMsg = history.firstWhere(
        (m) => m.role == ChatRole.user,
        orElse: () => history.first,
      );

      final questionText = firstUserMsg.content.trim();
      if (questionText.isEmpty) {
        await _syncSessionsFromStorage();
        return;
      }

      String title = await AiChatService.completeChat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: [
          {
            'role': 'system',
            'content':
                '你是一个对话标题生成器。只输出一个不超过10个字的简短标题，不要回答问题，不要打招呼，不要解释，不要带引号或句末标点。',
          },
          {
            'role': 'user',
            'content':
                '请将以下用户提问总结为一个不超过10个字的对话标题（只输出标题文本，不要回答或寒暄）：\n<question>\n$questionText\n</question>',
          },
        ],
        provider: provider,
        maxTokens: 120,
        timeout: const Duration(seconds: 15),
      );
      title = title
          .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim()
          .replaceAll('"', '')
          .replaceAll("'", '');
      title = AppTextUtils.truncate(title, 15, ellipsis: '...');
      if (title.isEmpty) {
        final content = firstUserMsg.content.trim();
        if (content.isEmpty) {
          await _syncSessionsFromStorage();
          return;
        }
        title = AppTextUtils.truncate(content, 15, ellipsis: '...');
      }

      await ChatStorageService.updateSessionTitle(sessionId, title);
      if (!mounted) return;
      final idx = _sessions.indexWhere((s) => s.id == sessionId);
      if (idx != -1) {
        setState(() {
          _sessions[idx].title = title;
          _sessions[idx].updatedAt = DateTime.now();
        });
      } else {
        await _syncSessionsFromStorage();
      }
    } catch (_) {
      await _syncSessionsFromStorage();
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: '清空聊天记录',
      message: '确定要清空所有聊天记录吗？此操作不可恢复。',
      confirmLabel: '清空',
    );

    if (confirmed) {
      await ChatStorageService.clearHistory();
      if (mounted) {
        setState(() {
          _messages = [];
          _sessions.removeWhere((s) => s.id == _activeSessionId);
        });
      }
    }
  }

  Future<void> _showPromptSettings() async {
    await _showPromptSettingsFromSource(_settingsKey);
  }

  Future<void> _showPromptSettingsFromSource(GlobalKey sourceKey) async {
    final colorScheme = Theme.of(context).colorScheme;
    await PageTransitions.pushFromRect<void>(
      context: context,
      page: const AiAssistantSettingsPage(),
      sourceKey: sourceKey,
      sourceColor: colorScheme.brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      sourceBorderRadius: BorderRadius.circular(24),
      placeholderBuilder: (_) =>
          Icon(Icons.tune_rounded, color: colorScheme.primary, size: 30),
    );
    if (!mounted) return;
    await Future.wait([_loadPromptSettings(), _loadDeepThinking()]);
  }
}
