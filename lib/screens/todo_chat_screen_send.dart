part of 'todo_chat_screen.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

final RegExp _planningProposalRequestPattern = RegExp(
  r'生成|确认|确定|^可以|^要的|^好的|^需要',
);
final RegExp _confirmPendingPlanningDraftPattern = RegExp(
  r'^(?:确认|确定|确认保存|确认并保存|保存)[！!。\.\s]*$',
);
final RegExp _pickupCluePattern = RegExp(r'取餐|取件|取货|餐号|取单号|取餐码|取件码|外卖|快递');
final RegExp _pendingNoticePattern = RegExp(
  r'待确认|尚未(?:写入|保存|入账|执行)|点击.{0,14}(?:执行|保存|确认删除)',
);
final RegExp _punctuationStripPattern = RegExp(r'[\s，。！？、,.!?]');
final RegExp _dateCorrectionPattern = RegExp(
  r'(?:\d{2,4}\s*年|\d{1,2}\s*月|\d{1,2}\s*(?:日|号)|\d{4}[-/.]\d{1,2})',
);

mixin _TodoChatSend on _TodoChatScreenStateBase {
  bool _openingVoiceInput = false;

  ChatUsageSummary? _takePendingVoiceUsageSummary() {
    final usage = _pendingVoiceUsageSummary;
    _pendingVoiceUsageSummary = null;
    return usage;
  }

  List<AiTodoAction> _pendingCountdownDraftActions() => _messages
      .where((message) => message.role == ChatRole.assistant)
      .expand((message) => message.todoActions ?? const <AiTodoAction>[])
      .where(
        (action) =>
            action.type == AiTodoActionType.createCountdown &&
            !action.isAdded &&
            !action.isIgnored,
      )
      .toList(growable: false);

  bool _hasUnresolvedCountdownTeamBinding(AiTodoAction action) {
    if (action.type != AiTodoActionType.createCountdown) return false;
    final name = action.teamName?.trim() ?? '';
    final uuid = action.teamUuid?.trim() ?? '';
    if (name.isEmpty && uuid.isEmpty) return false;

    final team = AiTeamBindingResolver.resolveReference(
      name: name,
      uuid: uuid,
      teams: _teams,
    );
    if (team == null) return true;
    action
      ..teamName = team.name
      ..teamUuid = team.uuid
      ..hasTeamUuid = true;
    return false;
  }

  List<AiTodoAction> _buildPendingCountdownTitleReplacement({
    required List<AiTodoAction> previousDrafts,
    required String suffix,
    required Team? requestedTeam,
    required String originalText,
  }) {
    if (previousDrafts.isEmpty) return const [];

    final replacements = <AiTodoAction>[];
    for (final previous in previousDrafts) {
      final title = previous.title?.trim() ?? '';
      final dueDate = previous.dueDate?.trim();
      if (previous.type != AiTodoActionType.createCountdown ||
          title.isEmpty ||
          dueDate == null ||
          dueDate.isEmpty) {
        return const [];
      }

      final replacement = AiTodoAction.fromJson(previous.toJson())
        ..title = title.endsWith(suffix) ? title : '$title$suffix'
        ..originalText = originalText
        ..isAdded = false
        ..isIgnored = false
        ..isSelected = true;
      if (requestedTeam != null) {
        replacement
          ..teamName = requestedTeam.name
          ..teamUuid = requestedTeam.uuid
          ..hasTeamUuid = true;
      }
      replacements.add(replacement);
    }
    return replacements;
  }

  bool _supersedePendingCountdownDrafts(Set<AiTodoAction> previousDrafts) {
    var changed = false;
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      final actions = message.todoActions;
      if (message.role != ChatRole.assistant || actions == null) continue;
      var messageChanged = false;
      final replacements = actions
          .map((action) {
            if (!previousDrafts.contains(action)) return action;
            final ignored = AiTodoAction.fromJson(action.toJson())
              ..isIgnored = true;
            messageChanged = true;
            return ignored;
          })
          .toList(growable: false);
      if (messageChanged) {
        _messages[index] = message.copyWith(todoActions: replacements);
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _finishPendingCountdownTitleEditLocally({
    required String sessionId,
    required String originalText,
    required String suffix,
    required List<AiTodoAction> previousDrafts,
    required bool hasRequestedTeamBinding,
    required String? requestedTeamName,
    required Team? requestedTeam,
  }) async {
    final replacements = _buildPendingCountdownTitleReplacement(
      previousDrafts: previousDrafts,
      suffix: suffix,
      requestedTeam: requestedTeam,
      originalText: originalText,
    );
    final hasUnresolvedTeamBinding =
        (hasRequestedTeamBinding && requestedTeam == null) ||
        replacements.any(_hasUnresolvedCountdownTeamBinding);
    final isValid =
        !hasUnresolvedTeamBinding &&
        replacements.length == previousDrafts.length;
    final todoActions = isValid ? replacements : const <AiTodoAction>[];
    late final String content;
    if (hasRequestedTeamBinding && requestedTeam == null) {
      content =
          '本地团队列表中没有找到唯一匹配的团队「${requestedTeamName ?? '本轮指定团队'}」，旧草案已保留，应用没有替换或写入数据。请核对团队名称后重试。';
    } else if (hasUnresolvedTeamBinding) {
      content = '现有倒计时的团队归属无法匹配本地团队，旧草案已保留，应用没有替换或写入数据。请先核对团队后重试。';
    } else if (isValid) {
      content =
          '应用已按现有草案生成全部倒计时标题修订卡，追加“$suffix”，并保留原截止时间${requestedTeam == null ? '和原团队归属' : '，绑定到本地团队「${requestedTeam.name}」'}。旧草案已由新草案替换；请核对新卡片后执行。';
    } else {
      content = '现有待确认倒计时草案缺少标题或截止时间，无法安全生成完整替换卡；旧草案已保留，应用没有写入数据。';
    }
    final assistantContent = _appendPendingWriteConfirmationNotice(
      content: content,
      todoActions: todoActions,
      financeDrafts: const [],
      financeActions: const [],
    );
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: assistantContent,
      rawContent: assistantContent,
      smartContext: _lastRequestSmartContext,
      todoActions: todoActions.isNotEmpty ? todoActions : null,
    );

    var supersededCountdownDrafts = false;
    setState(() {
      if (isValid) {
        supersededCountdownDrafts = _supersedePendingCountdownDrafts(
          previousDrafts.toSet(),
        );
      }
      _messages.add(assistantMsg);
      _streamingContent = '';
      _streamingReasoning = '';
      _streamingToolCalls = [];
      _streamingFinishReason = null;
      _isLoading = false;
      _cancelGeneration = null;
      _suggestions = [];
      if (todoActions.isNotEmpty) _actionRailCollapsed = false;
    });
    await ChatStorageService.addMessage(assistantMsg, sessionId: sessionId);
    if (supersededCountdownDrafts) await _saveHistorySilently();
    _scrollToBottom();
    _generateSessionTitle(sessionId: sessionId);
  }

  Set<String> _parsedCdtActionNames(Iterable<AiTodoAction> actions) {
    final names = <String>{};
    for (final action in actions) {
      final name = switch (action.type) {
        AiTodoActionType.createTodo => 'create_todo',
        AiTodoActionType.createHabit => 'create_habit',
        AiTodoActionType.updateHabit => 'update_habit',
        AiTodoActionType.deleteHabit => 'delete_habit',
        AiTodoActionType.updateTodo => 'update_todo',
        AiTodoActionType.completeTodo => 'complete_todo',
        AiTodoActionType.skipTodo => 'skip_todo',
        AiTodoActionType.deleteTodo => 'delete_todo',
        AiTodoActionType.createFixedSchedule => 'create_schedule',
        AiTodoActionType.updateFixedSchedule => 'update_schedule',
        AiTodoActionType.cancelFixedSchedule => 'cancel_schedule',
        AiTodoActionType.deleteFixedSchedule => 'delete_schedule',
        AiTodoActionType.rescheduleTodo ||
        AiTodoActionType.bulkRescheduleTodo => 'reschedule_todo',
        AiTodoActionType.categorizeTodo => 'categorize_todo',
        AiTodoActionType.createPlanBlock ||
        AiTodoActionType.planTodos => 'create_plan_block',
        AiTodoActionType.updatePlanBlock => 'update_plan_block',
        AiTodoActionType.deletePlanBlock => 'delete_plan_block',
        AiTodoActionType.reschedulePlanBlocks => 'reschedule_plan_blocks',
        AiTodoActionType.skipPlanBlock => 'skip_plan_block',
        AiTodoActionType.startPlanBlockPomodoro => 'start_plan_block_pomodoro',
        AiTodoActionType.splitTodo => 'split_todo',
        AiTodoActionType.mergeTodos => 'merge_todos',
        AiTodoActionType.createTimeLog => 'create_time_log',
        AiTodoActionType.updateTimeLog => 'update_time_log',
        AiTodoActionType.deleteTimeLog => 'delete_time_log',
        AiTodoActionType.startPomodoro => 'start_pomodoro',
        AiTodoActionType.stopPomodoro => 'stop_pomodoro',
        AiTodoActionType.createCountdown => 'create_countdown',
        AiTodoActionType.updateCountdown => 'update_countdown',
        AiTodoActionType.completeCountdown => 'complete_countdown',
        AiTodoActionType.deleteCountdown => 'delete_countdown',
        AiTodoActionType.createTodoGroup => 'create_todo_group',
        AiTodoActionType.updateTodoGroup => 'update_todo_group',
        AiTodoActionType.deleteTodoGroup => 'delete_todo_group',
        AiTodoActionType.createPomodoroTag => 'create_pomodoro_tag',
        AiTodoActionType.updatePomodoroTag => 'update_pomodoro_tag',
        AiTodoActionType.deletePomodoroTag => 'delete_pomodoro_tag',
        AiTodoActionType.unknown => '',
      };
      if (name.isNotEmpty) names.add(name);
      if (action.type == AiTodoActionType.createPlanBlock &&
          action.newTodoTitle?.trim().isNotEmpty == true) {
        names.add('create_todo');
      }
    }
    return names;
  }

  int _parsedTodoCreationCount(Iterable<AiTodoAction> actions) =>
      actions
          .where(
            (action) =>
                action.type == AiTodoActionType.createTodo &&
                action.title?.trim().isNotEmpty == true,
          )
          .length +
      actions
          .where(
            (action) =>
                action.type == AiTodoActionType.createPlanBlock &&
                action.newTodoTitle?.trim().isNotEmpty == true,
          )
          .length;

  Future<void> _openVoiceInput() async {
    if (_isLoading || _openingVoiceInput || _pendingAttachment != null) return;
    _openingVoiceInput = true;
    try {
      final globalConfig = await LLMService.getConfig();
      final hasChatApi =
          (_chatModel.isNotEmpty && _chatApiKey.isNotEmpty) ||
          (globalConfig?.isConfigured ?? false);
      final key = await MimoAsrService.resolveApiKey(
        chatConfig: {
          'provider': _chatProvider,
          'apiUrl': _chatApiUrl,
          'apiKey': _chatApiKey,
        },
      );
      if (!mounted) return;
      if (!hasChatApi || key.isEmpty) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: const Text('请配置 AI 对话模型，并填写普通小米 MiMo API Key 以识别语音'),
            action: SnackBarAction(label: '配置', onPressed: _openLlmConfigPage),
          ),
        );
        return;
      }
      if (!await MinorModeService.instance.authorizeAiInteraction()) return;
      if (!mounted) return;
      ChatUsageSummary? voiceUsage;
      final text = await showAppModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        useGlassSheet: false,
        builder: (_) => QuickVoiceChatSheet(
          apiKey: key,
          onUsageSummary: (usage) => voiceUsage = usage,
        ),
      );
      if (!mounted || text == null || _isLoading) return;
      _pendingVoiceUsageSummary = ChatUsageSummary.combine([
        ?_pendingVoiceUsageSummary,
        ?voiceUsage,
      ]);
      // Preserve a typed draft; otherwise send in this session for follow-ups.
      final draft = _inputCtrl.text.trim();
      _inputCtrl.text = draft.isEmpty ? text : '$draft\n$text';
      if (draft.isEmpty) await _sendMessage();
    } catch (_) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('无法打开语音对话，请稍后重试')),
        );
      }
    } finally {
      _openingVoiceInput = false;
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    final attachment = _pendingAttachment;
    if ((text.isEmpty && attachment == null) || _isLoading) return;

    // The explicit #记账 format is intentionally handled locally. This keeps
    // a simple import usable without an AI key and makes its result editable
    // immediately; natural-language finance requests still go through the
    // assistant below.
    if (attachment == null) {
      if (await _tryHandleExplicitFinanceText(text)) return;
      if (await _tryConfirmPendingFinanceDraft(text)) return;
      if (await _tryRevealPendingPlanningDraft(text)) return;
      if (await _tryConfirmPendingPlanningDraft(text)) return;
    }

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
        if (!mounted) return;
        final goToSettings = await showAppDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('未配置大模型'),
            content: const Text('可以先配置API地址和密钥，也可以复制完整提示词到外部AI，稍后把回复粘贴回来识别。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx, false);
                  _copyManualPromptFromInput();
                },
                icon: const Icon(Icons.content_copy_rounded, size: 16),
                label: const Text('复制提示词'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx, false);
                  _pasteManualReplyFromClipboard();
                },
                icon: const Icon(Icons.assignment_rounded, size: 16),
                label: const Text('粘贴识别'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去配置'),
              ),
            ],
          ),
        );
        if (goToSettings == true && mounted) {
          await _openLlmConfigPage();
        }
        return;
      }
    }

    // Binary multimodal inputs use the configured multimodal model. Plain
    // text documents are expanded into a guarded text block and can stay on
    // the current conversation model.
    if (attachment != null &&
        !AiMultimodalMessageBuilder.isTextDocument(attachment)) {
      final visionConfig = await LLMService.getConfig();
      if (visionConfig != null &&
          visionConfig.isConfigured &&
          visionConfig.visionModel.trim().isNotEmpty) {
        final configuredVisionProvider =
            visionConfig.visionProvider?.trim() ?? '';
        final visionProvider = configuredVisionProvider.isNotEmpty
            ? configuredVisionProvider
            : visionConfig.provider;
        final endpoint = await LLMService.resolveVisionEndpoint(
          visionConfig.visionModel,
          provider: visionProvider,
        );
        model = visionConfig.visionModel;
        provider = visionProvider;
        apiUrl = endpoint.url.isNotEmpty ? endpoint.url : visionConfig.apiUrl;
        apiKey = endpoint.key.isNotEmpty ? endpoint.key : visionConfig.apiKey;
        final capabilities = await LLMService.getMultimodalCapabilities(
          visionConfig.visionModel,
          provider: visionProvider,
        );
        final requiredCapability = switch (attachment.kind) {
          ChatAttachmentKind.image => 'image',
          ChatAttachmentKind.audio => 'audio',
          ChatAttachmentKind.video => 'video',
          ChatAttachmentKind.document => 'file',
        };
        if (!capabilities.contains(requiredCapability)) {
          if (mounted) {
            AppSnackBars.showSnackBar(
              context,
              SnackBar(
                content: Text(
                  '当前多模态模型不支持${attachment.typeLabel}输入，'
                  '请在“模型与 API 配置”中更换模型。',
                ),
              ),
            );
          }
          return;
        }
      } else {
        if (mounted) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(content: Text('请先配置支持该输入的多模态模型')),
          );
        }
        return;
      }
    }

    if (apiUrl.isEmpty) apiUrl = AiChatService.defaultApiUrl;
    final nativeToolMode = AiChatService.supportsFunctionTools(
      provider: provider,
      apiUrl: apiUrl,
      model: model,
    );
    final fallbackFromFunctionCallingContext =
        _smartContext &&
        _contextMode == AiContextMode.functionCalling &&
        !nativeToolMode;
    final useContextInjection =
        _usesContextInjection || fallbackFromFunctionCallingContext;
    if (fallbackFromFunctionCallingContext) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text(
              '当前模型或 API 接口尚未接入原生 Function Calling；'
              '本轮将使用智能注入与兼容操作协议，写操作仍需在确认卡中确认。',
            ),
          ),
        );
      }
    }
    final sessionId = _activeSessionId;
    if (sessionId == null) return;

    var attachmentForMessage = attachment;
    if (attachment != null) {
      try {
        final persistedPath =
            attachment.path.isNotEmpty && !attachment.path.startsWith('data:')
            ? await persistImagePath(attachment.path, 'chat_attachments')
            : attachment.bytes == null
            ? null
            : await persistImageBytes(
                attachment.bytes!,
                'chat_attachments',
                attachment.name,
              );
        if (persistedPath != null && persistedPath.isNotEmpty) {
          attachmentForMessage = ChatImageAttachment(
            path: persistedPath,
            name: attachment.name,
            mimeType: attachment.mimeType,
            sizeBytes: attachment.sizeBytes,
            bytes: attachment.bytes,
            kind: attachment.kind,
          );
        }
      } catch (_) {
        // The in-memory bytes remain usable even if a durable copy is not
        // available (for example, a content URI on Android).
      }
    }

    final userMsg = ChatMessage(
      role: ChatRole.user,
      content: AiMultimodalMessageBuilder.requestTextForAttachment(
        text: text,
        attachmentKind: attachment?.kind,
      ),
      attachment: attachmentForMessage,
      usageSummary: _takePendingVoiceUsageSummary(),
    );
    final requestText = userMsg.content;
    final previousUserMessage = _latestUserTextFromHistory();
    final previousAssistantMessage = _latestAssistantMessageForActionRouting();
    final pendingCountdownTitleEditSuffix =
        AiTodoContextBuilder.pendingCountdownTitleSuffixForRequest(
          requestText,
          previousUserMessage: previousUserMessage,
          previousAssistantMessage: previousAssistantMessage,
        );
    final hasRequestedCountdownTeamBinding =
        AiTeamBindingResolver.hasExplicitBindingIntent(requestText);
    final requestedCountdownTeam = hasRequestedCountdownTeamBinding
        ? AiTeamBindingResolver.requestedTeam(requestText, teams: _teams)
        : null;
    final requestedCountdownTeamName = hasRequestedCountdownTeamBinding
        ? AiTeamBindingResolver.requestedTeamName(requestText, teams: _teams)
        : null;
    final pendingCountdownDraftsToReplace =
        pendingCountdownTitleEditSuffix == null
        ? const <AiTodoAction>[]
        : _pendingCountdownDraftActions();
    final isPendingCountdownTitleEdit =
        pendingCountdownTitleEditSuffix != null &&
        pendingCountdownDraftsToReplace.isNotEmpty;
    // Keep read queries registered on every Function Calling turn. The model
    // decides when to call them; only an invocation reads app data.
    final useQueryTools =
        _smartContext &&
        _contextMode == AiContextMode.functionCalling &&
        nativeToolMode;

    setState(() {
      _messages.add(userMsg);
      _ensureActiveSessionInList();
      _streamingContent = '';
      _streamingReasoning = '';
      _streamingToolCalls = [];
      _queryToolResults.clear();
      _streamingFinishReason = null;
      _suggestions = [];
      _isLoading = true;
      _pendingAttachment = null;
    });
    await ChatStorageService.addMessage(userMsg, sessionId: sessionId);
    _inputCtrl.clear();
    _scrollToBottom();

    _cancelGeneration = Completer<void>();
    ChatUsageSummary? usageSummary;

    try {
      if (isPendingCountdownTitleEdit) {
        await _finishPendingCountdownTitleEditLocally(
          sessionId: sessionId,
          originalText: requestText,
          suffix: pendingCountdownTitleEditSuffix,
          previousDrafts: pendingCountdownDraftsToReplace,
          hasRequestedTeamBinding: hasRequestedCountdownTeamBinding,
          requestedTeamName: requestedCountdownTeamName,
          requestedTeam: requestedCountdownTeam,
        );
        return;
      }

      final conversationContext = _recentConversationTextForContext(
        excludingMessageId: userMsg.id,
      );
      final financeContext = useContextInjection
          ? await FinanceAiContextService.buildContext(
              userMessage: requestText,
              conversationContext: conversationContext,
              previousUserMessage: previousUserMessage,
              dateRangeOverride: _financeContextDateRangeOverride(),
            )
          : '';
      final habitContext = useContextInjection
          ? await HabitAiContextService.buildContext(
              userMessage: requestText,
              conversationContext: conversationContext,
              previousUserMessage: previousUserMessage,
              goals: _habitGoals,
            )
          : '';
      final nativeTools = nativeToolMode
          ? <Map<String, dynamic>>[
              if (!AiNativeToolDefinitionBuilder.isMissingActionCardReport(
                    requestText,
                  ) &&
                  AiSettingsNavigationService.shouldOfferForRequest(
                    requestText,
                  ))
                AiSettingsNavigationService.buildDefinition(),
              if (_memoryEnabled) AiMemoryService.buildDefinition(),
              if (useQueryTools) ...AiQueryToolService.buildDefinitions(),
              ...AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
                requestText,
                previousUserMessage: previousUserMessage,
                previousAssistantMessage: previousAssistantMessage,
                availableTeams: _teams,
              ),
            ]
          : null;
      final fallbackWriteTools = nativeToolMode
          ? const <Map<String, dynamic>>[]
          : AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
                  requestText,
                  previousUserMessage: previousUserMessage,
                  previousAssistantMessage: previousAssistantMessage,
                  availableTeams: _teams,
                )
                .where((tool) {
                  final name =
                      (tool['function'] as Map)['name']?.toString() ?? '';
                  return name.startsWith('propose_') &&
                      name != AiSettingsNavigationService.toolName;
                })
                .toList(growable: false);
      if (fallbackWriteTools.isNotEmpty &&
          !fallbackFromFunctionCallingContext &&
          mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text(
              '当前模型或 API 接口未接入原生 Function Calling，'
              '本轮将尝试兼容操作协议；只有出现确认卡并点击操作按钮后才会写入。',
            ),
          ),
        );
      }
      final proposalToolDefinitions = nativeToolMode
          ? nativeTools
          : fallbackWriteTools;
      final allowedNativeToolNames =
          AiNativeToolDefinitionBuilder.allowedToolNames(nativeTools);
      final allowedCdtActionNames =
          AiNativeToolDefinitionBuilder.allowedCdtActionNames(
            proposalToolDefinitions,
          );
      final allowedFinanceActionNames =
          AiNativeToolDefinitionBuilder.allowedFinanceActionNames(
            proposalToolDefinitions,
          );
      final allowedProposalToolNames =
          AiNativeToolDefinitionBuilder.allowedToolNames(
            proposalToolDefinitions,
          );
      final requiredFallbackTodoCount =
          !nativeToolMode && allowedCdtActionNames.contains('create_todo')
          ? AiTodoContextBuilder.explicitTodoCreationCount(requestText)
          : null;
      final requiredFallbackFinanceDraftCount =
          !nativeToolMode &&
              allowedProposalToolNames.contains('propose_finance_drafts')
          ? AiTodoContextBuilder.explicitFinanceDraftCount(requestText)
          : null;
      final requiredFallbackCdtActionNames = nativeToolMode
          ? const <String>{}
          : {
              ...AiTodoContextBuilder.requiredExplicitCdtActionNames(
                requestText,
                previousUserMessage: previousUserMessage,
                previousAssistantMessage: previousAssistantMessage,
              ).intersection(allowedCdtActionNames),
              if (requiredFallbackTodoCount != null) 'create_todo',
            };
      const actionsRequiringKnownTodoIds = {
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
      final needsKnownTodoReferences = allowedCdtActionNames.any(
        actionsRequiringKnownTodoIds.contains,
      );
      final knownTodoTitlesForToolValidation =
          nativeToolMode && needsKnownTodoReferences
          ? await _existingTodoTitleMap(allowedCdtActionNames)
          : null;
      const actionsRequiringKnownHabitIds = {'update_habit', 'delete_habit'};
      final needsKnownHabitReferences = allowedCdtActionNames.any(
        actionsRequiringKnownHabitIds.contains,
      );
      final knownHabitIdsForToolValidation =
          nativeToolMode && needsKnownHabitReferences
          ? (await HabitRepository.getGoals()).map((goal) => goal.uuid).toSet()
          : null;
      final financeTransactionIds = _rxCached19_1
          .allMatches(financeContext)
          .map((match) => match.group(1)!)
          .toSet();
      final knownFinanceTransactionIdsForToolValidation =
          nativeToolMode && financeTransactionIds.isNotEmpty
          ? financeTransactionIds
          : null;
      Map<String, Set<String>>? knownFinanceCatalogIdsByKindForToolValidation;
      if (nativeToolMode &&
          allowedProposalToolNames.any(
            const {
              'propose_finance_drafts',
              'propose_finance_actions',
            }.contains,
          )) {
        try {
          final categories = await FinanceRepository.getCategories();
          final paymentMethods = await FinanceRepository.getPaymentMethods();
          knownFinanceCatalogIdsByKindForToolValidation = {
            'category': categories.map((item) => item.uuid).toSet(),
            'payment_method': paymentMethods.map((item) => item.uuid).toSet(),
          };
        } catch (_) {
          // Fail closed for supplied references without interrupting the chat.
          knownFinanceCatalogIdsByKindForToolValidation = const {
            'category': <String>{},
            'payment_method': <String>{},
          };
        }
      }
      final knownReferenceIdsByDomain = nativeToolMode
          ? await _loadKnownReferenceIdsByDomain(allowedCdtActionNames)
          : const <String, Set<String>>{};
      final effectiveChatProvider = AiChatService.effectiveProvider(
        provider,
        apiUrl,
      );
      final includeReasoningContent =
          nativeToolMode &&
          (effectiveChatProvider == 'deepseek' ||
              (AiChatService.usesMimoChatProtocol(provider, apiUrl) &&
                  _deepThinking));
      final List<Map<String, dynamic>> apiMessages =
          await _buildApiMessagesForRequest(
            financeContext: financeContext,
            habitContext: habitContext ?? '',
            provider: provider,
            nativeToolCalls: nativeToolMode,
            includeReasoningContent: includeReasoningContent,
            contextInjection: useContextInjection,
            queryTools: useQueryTools,
          );
      String fullContent = '';
      String? latestRawModelReply;
      String reasoningContent = '';
      final nativeToolCalls = <AiChatFunctionCall>[];
      final toolCallProgress = <int, ChatNativeToolCall>{};
      final usageSummaries = <ChatUsageSummary>[];

      Stream<AiChatStreamChunk> streamRound(
        List<Map<String, dynamic>> messages,
        List<Map<String, dynamic>> tools, {
        String? toolChoiceName,
      }) => AiChatService.streamChat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
        deepThinking: _deepThinking,
        provider: provider,
        cancelToken: _cancelGeneration,
        imageCount: attachment?.kind == ChatAttachmentKind.image ? 1 : 0,
        tools: tools,
        toolChoiceName: toolChoiceName,
      );
      final responseStream = nativeToolMode
          ? AiToolChatRunner.run(
              messages: apiMessages,
              tools: nativeTools!,
              streamRound: streamRound,
              streamProposalRound: (messages, tools) {
                final proposalTools = tools.where((tool) {
                  final function = tool['function'];
                  return function is Map &&
                      (function['name'] as String? ?? '').startsWith(
                        'propose_',
                      );
                }).toList();
                final planningToolAvailable = proposalTools.any((tool) {
                  final function = tool['function'] as Map;
                  return function['name'] == 'propose_cdt_actions' &&
                      jsonEncode(function['parameters'])
                          .contains('create_plan_block');
                });
                final hasReadTools = tools.any((tool) {
                  final function = tool['function'];
                  return function is Map &&
                      AiQueryToolService.toolNames.contains(function['name']);
                });
                final proposalToolChoice = planningToolAvailable
                    ? 'propose_cdt_actions'
                    : proposalTools.length == 1 && !hasReadTools
                    ? (proposalTools.single['function'] as Map)['name']
                          as String
                    : null;
                final effectiveProvider = AiChatService.effectiveProvider(
                  provider,
                  apiUrl,
                );
                final supportsNamedToolChoice =
                    (effectiveProvider == 'deepseek' && !_deepThinking) ||
                    effectiveProvider == 'nvidia_nim';
                return streamRound(
                  messages,
                  tools,
                  toolChoiceName: supportsNamedToolChoice
                      ? proposalToolChoice
                      : null,
                );
              },
              executeRead: _createQueryToolService().execute,
              cancelToken: _cancelGeneration,
              includeReasoningContent: includeReasoningContent,
              planningRequestText: requestText,
              previousUserMessage: previousUserMessage,
              previousAssistantMessage: previousAssistantMessage,
              knownTodoIds: knownTodoTitlesForToolValidation?.keys.toSet(),
              knownHabitIds: knownHabitIdsForToolValidation,
              knownFinanceTransactionIds:
                  knownFinanceTransactionIdsForToolValidation,
              knownFinanceCatalogIdsByKind:
                  knownFinanceCatalogIdsByKindForToolValidation,
              knownReferenceIdsByDomain: knownReferenceIdsByDomain,
              maxQueryRounds: _toolBudget.maxQueryRounds,
              maxCalls: _toolBudget.maxCalls,
              maxTurnChars: _toolBudget.maxTurnChars,
              onManageMemory: _memoryEnabled
                  ? (arguments) => AiMemoryService.executeToolCall(
                      widget.username,
                      arguments,
                    )
                  : null,
              requirePlanningProposal:
                  (_planningProposalRequestPattern.hasMatch(requestText) ||
                      AiNativeToolDefinitionBuilder.isMissingActionCardReport(
                        requestText,
                      )) &&
                  allowedCdtActionNames.contains('create_plan_block'),
            )
          : streamRound(apiMessages, nativeTools ?? []);
      await for (final chunk in responseStream) {
        if (chunk.rawModelReply != null) {
          latestRawModelReply = chunk.rawModelReply;
        }
        if (chunk.usageSummary != null) {
          usageSummaries.add(chunk.usageSummary!);
          usageSummary = ChatUsageSummary.combine(usageSummaries);
        }
        _queryToolResults.addAll(chunk.toolResults);
        if (chunk.finishReason != null && chunk.finishReason!.isNotEmpty) {
          if (mounted) {
            _streamingFinishReason = chunk.finishReason;
            _notifyStreamingBubbleChanged();
          }
        }
        if (chunk.reasoningContent.isNotEmpty) {
          reasoningContent += chunk.reasoningContent;
          if (mounted) {
            _streamingReasoning = reasoningContent;
            _notifyStreamingBubbleChanged();
            _scrollToBottom();
          }
        }
        if (chunk.toolCallDeltas.isNotEmpty) {
          for (final delta in chunk.toolCallDeltas) {
            final previous = toolCallProgress[delta.index];
            toolCallProgress[delta.index] = ChatNativeToolCall(
              id: delta.id?.isNotEmpty == true ? delta.id! : previous?.id ?? '',
              name: '${previous?.name ?? ''}${delta.name}',
              arguments: '${previous?.arguments ?? ''}${delta.arguments}',
              argumentsComplete: false,
            );
          }
        }
        nativeToolCalls.addAll(chunk.toolCalls);
        if (mounted &&
            (chunk.toolCallDeltas.isNotEmpty ||
                chunk.toolCalls.isNotEmpty ||
                chunk.toolResults.isNotEmpty)) {
          final completeIds = nativeToolCalls.map((call) => call.id).toSet();
          final progressEntries = toolCallProgress.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          _streamingToolCalls = [
            for (final call in nativeToolCalls)
              ChatNativeToolCall(
                id: call.id,
                name: call.name,
                arguments: call.arguments,
                result: _queryToolResults[call.id],
                resultSummary: _queryToolResults.containsKey(call.id)
                    ? _queryResultSummary(_queryToolResults[call.id])
                    : '',
              ),
            for (final entry in progressEntries)
              if (!completeIds.contains(entry.value.id)) entry.value,
          ];
          _notifyStreamingBubbleChanged();
          _scrollToBottom();
        }
        if (chunk.content.isNotEmpty) {
          fullContent += chunk.content;
          if (mounted) {
            _streamingContent = fullContent;
            _notifyStreamingBubbleChanged();
            _scrollToBottom();
          }
        }
      }
      latestRawModelReply ??= AiNativeToolCallParser.formatRawReply(
        fullContent,
        nativeToolCalls,
      );

      if (!nativeToolMode) {
        final retryResult = await _retryMissingFallbackProposalBlocks(
          fullContent: fullContent,
          reasoningContent: reasoningContent,
          latestRawModelReply: latestRawModelReply,
          apiMessages: apiMessages,
          fallbackWriteTools: fallbackWriteTools,
          allowedProposalToolNames: allowedProposalToolNames,
          requiredFallbackCdtActionNames: requiredFallbackCdtActionNames,
          requiredFallbackTodoCount: requiredFallbackTodoCount,
          requiredFallbackFinanceDraftCount: requiredFallbackFinanceDraftCount,
          streamRound: streamRound,
          usageSummaries: usageSummaries,
          usageSummary: usageSummary,
        );
        fullContent = retryResult.fullContent;
        reasoningContent = retryResult.reasoningContent;
        latestRawModelReply = retryResult.latestRawModelReply;
        usageSummary = retryResult.usageSummary;
      }

      final actionContent = AiNativeToolCallParser.appendToAssistantText(
        fullContent,
        nativeToolCalls,
        allowedToolNames: allowedNativeToolNames,
        allowedCdtActionNames: allowedCdtActionNames,
        allowedFinanceActionNames: allowedFinanceActionNames,
      );
      final settingsTargets =
          AiNativeToolDefinitionBuilder.isMissingActionCardReport(
                requestText,
              ) ||
              !AiSettingsNavigationService.shouldOfferForRequest(requestText)
          ? <String>[]
          : AiSettingsNavigationService.extractTargets(actionContent);
      final rawModelReply = latestRawModelReply;
      final existingTodoTitles = await _existingTodoTitleMap(
        allowedCdtActionNames,
      );

      // 用户主动打断：保存已有内容为部分回复
      if (_cancelGeneration?.isCompleted == true) {
        await _persistInterruptedAssistantReply(
          sessionId: sessionId,
          requestText: requestText,
          nativeToolMode: nativeToolMode,
          fullContent: fullContent,
          actionContent: actionContent,
          rawModelReply: rawModelReply,
          reasoningContent: reasoningContent,
          usageSummary: usageSummary,
          nativeToolCalls: nativeToolCalls,
          allowedCdtActionNames: allowedCdtActionNames,
          allowedFinanceActionNames: allowedFinanceActionNames,
          allowedProposalToolNames: allowedProposalToolNames,
          settingsTargets: settingsTargets,
          existingTodoTitles: existingTodoTitles,
        );
        return;
      }

      await _finalizeStreamedAssistantReply(
        sessionId: sessionId,
        requestText: requestText,
        nativeToolMode: nativeToolMode,
        hasRequestedCountdownTeamBinding: hasRequestedCountdownTeamBinding,
        requestedCountdownTeam: requestedCountdownTeam,
        requestedCountdownTeamName: requestedCountdownTeamName,
        fallbackWriteTools: fallbackWriteTools,
        fullContent: fullContent,
        actionContent: actionContent,
        rawModelReply: rawModelReply,
        reasoningContent: reasoningContent,
        usageSummary: usageSummary,
        nativeToolCalls: nativeToolCalls,
        allowedCdtActionNames: allowedCdtActionNames,
        allowedFinanceActionNames: allowedFinanceActionNames,
        allowedProposalToolNames: allowedProposalToolNames,
        requiredFallbackCdtActionNames: requiredFallbackCdtActionNames,
        requiredFallbackTodoCount: requiredFallbackTodoCount,
        requiredFallbackFinanceDraftCount: requiredFallbackFinanceDraftCount,
        settingsTargets: settingsTargets,
        existingTodoTitles: existingTodoTitles,
      );
    } catch (e) {
      await _handleSendMessageError(
        error: e,
        sessionId: sessionId,
        useQueryTools: useQueryTools,
        usageSummary: usageSummary,
      );
    }
  }
}

// Cached RegExp patterns
final RegExp _rxCached19_1 = RegExp(r'\[transactionId:\s*([^\]\s]+)\]');
