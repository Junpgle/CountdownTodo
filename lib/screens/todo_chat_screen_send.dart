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
      teams: widget.teams,
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

  String _fallbackCdtActionLabel(String name) => switch (name) {
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
    'create_todo_group' => '创建分类',
    'update_todo_group' => '修改分类',
    'delete_todo_group' => '删除分类',
    'create_pomodoro_tag' => '创建番茄标签',
    'update_pomodoro_tag' => '修改番茄标签',
    'delete_pomodoro_tag' => '删除番茄标签',
    _ => name,
  };

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
      final text = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
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
        ? AiTeamBindingResolver.requestedTeam(requestText, teams: widget.teams)
        : null;
    final requestedCountdownTeamName = hasRequestedCountdownTeamBinding
        ? AiTeamBindingResolver.requestedTeamName(
            requestText,
            teams: widget.teams,
          )
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
              if (useQueryTools) ...AiQueryToolService.buildDefinitions(),
              ...AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
                requestText,
                previousUserMessage: previousUserMessage,
                previousAssistantMessage: previousAssistantMessage,
                availableTeams: widget.teams,
              ),
            ]
          : null;
      final fallbackWriteTools = nativeToolMode
          ? const <Map<String, dynamic>>[]
          : AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
                  requestText,
                  previousUserMessage: previousUserMessage,
                  previousAssistantMessage: previousAssistantMessage,
                  availableTeams: widget.teams,
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
      final financeTransactionIds = RegExp(r'\[transactionId:\s*([^\]\s]+)\]')
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

      List<String> completeFallbackBlocks(
        String content,
        String start,
        String end,
      ) =>
          RegExp('${RegExp.escape(start)}[\\s\\S]*?${RegExp.escape(end)}')
              .allMatches(content)
              .map((match) => match.group(0)!)
              .toList();

      String normalizeFallbackCdtActionName(Object? value) {
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

      Set<String> fallbackCdtActionNames(String content) {
        final names = <String>{};
        for (final block in completeFallbackBlocks(
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
            for (final action
                in (decoded['actions'] as List).whereType<Map>()) {
              final name = normalizeFallbackCdtActionName(action['action']);
              if (name.isEmpty) continue;
              names.add(name);
              final rawBlocks =
                  action['blocks'] ?? action['plans'] ?? action['todos'];
              if (name == 'create_plan_block' && rawBlocks is List) {
                final createsTodo = rawBlocks.whereType<Map>().any(
                  (planned) =>
                      planned['newTodoTitle']?.toString().trim().isNotEmpty ==
                      true,
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

      int fallbackCreatedTodoCount(String content) {
        var count = 0;
        for (final block in completeFallbackBlocks(
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
            for (final rawAction
                in (decoded['actions'] as List).whereType<Map>()) {
              final name = normalizeFallbackCdtActionName(rawAction['action']);
              if (name == 'create_todo') {
                final rawTodos = rawAction['todos'];
                final todos = rawTodos is List ? rawTodos : [rawAction];
                count += todos.where((rawTodo) {
                  if (rawTodo is! Map) return false;
                  return rawTodo['title']?.toString().trim().isNotEmpty == true;
                }).length;
              } else if (name == 'create_plan_block') {
                final rawBlocks =
                    rawAction['blocks'] ??
                    rawAction['plans'] ??
                    rawAction['todos'];
                if (rawBlocks is! List) continue;
                count += rawBlocks
                    .whereType<Map>()
                    .where(
                      (planned) =>
                          planned['newTodoTitle']
                              ?.toString()
                              .trim()
                              .isNotEmpty ==
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

      int fallbackCreatedFinanceDraftCount(String content) =>
          FinanceTextParser.extractAssistantDrafts(content).length;

      List<String> fallbackFinanceBlocksForMissingCount(
        String content, {
        required int? remainingDraftCount,
      }) {
        final blocks = completeFallbackBlocks(
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
              Map value when value['entries'] is List =>
                value['entries'] as List,
              Map value when value['finance'] is List =>
                value['finance'] as List,
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

      Set<String> missingFallbackCdtActionNames(String content) {
        final missing = requiredFallbackCdtActionNames.difference(
          fallbackCdtActionNames(content),
        );
        if (requiredFallbackTodoCount != null &&
            fallbackCreatedTodoCount(content) < requiredFallbackTodoCount) {
          missing.add('create_todo');
        }
        return missing;
      }

      String fallbackMissingCdtActionLabel(String name, String content) {
        if (name != 'create_todo' || requiredFallbackTodoCount == null) {
          return _fallbackCdtActionLabel(name);
        }
        final remaining =
            requiredFallbackTodoCount - fallbackCreatedTodoCount(content);
        return remaining > 0
            ? '新建待办（还需 $remaining 条）'
            : _fallbackCdtActionLabel(name);
      }

      List<String> fallbackCdtBlocksForMissingActions(
        String content,
        Set<String> missingActions, {
        int? remainingTodoCount,
      }) {
        final blocks = completeFallbackBlocks(
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
              final name = normalizeFallbackCdtActionName(rawAction['action']);
              final action = Map<String, dynamic>.from(rawAction);
              if (name == 'create_todo' &&
                  missingActions.contains('create_todo')) {
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
                final rawBlocks = blockField == null
                    ? null
                    : action[blockField];
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

      Set<String> missingFallbackProposalBlocks(String content) {
        bool hasBlock(String start, String end) =>
            RegExp('${RegExp.escape(start)}[\\s\\S]*?${RegExp.escape(end)}')
                .hasMatch(content);

        return {
          if (allowedProposalToolNames.contains('propose_cdt_actions') &&
              (!hasBlock('[ACTION_START]', '[ACTION_END]') ||
                  missingFallbackCdtActionNames(content).isNotEmpty))
            'propose_cdt_actions',
          if (allowedProposalToolNames.contains('propose_finance_drafts') &&
              (!hasBlock('[FINANCE_START]', '[FINANCE_END]') ||
                  (requiredFallbackFinanceDraftCount != null &&
                      fallbackCreatedFinanceDraftCount(content) <
                          requiredFallbackFinanceDraftCount)))
            'propose_finance_drafts',
          if (allowedProposalToolNames.contains('propose_finance_actions') &&
              !hasBlock('[FINANCE_ACTION_START]', '[FINANCE_ACTION_END]'))
            'propose_finance_actions',
        };
      }

      String fallbackProposalLabel(String name) => switch (name) {
        'propose_cdt_actions' => '待办、习惯、日程或规划操作卡',
        'propose_finance_drafts' => '新增账单确认卡',
        'propose_finance_actions' => '账单修改确认卡',
        _ => name,
      };

      String fallbackMissingProposalLabel(String name, String content) {
        if (name == 'propose_finance_drafts' &&
            requiredFallbackFinanceDraftCount != null) {
          final remaining =
              requiredFallbackFinanceDraftCount -
              fallbackCreatedFinanceDraftCount(content);
          if (remaining > 0) return '新增账单确认卡（还需$remaining笔）';
        }
        return fallbackProposalLabel(name);
      }

      void appendFallbackBlocks(String blocks) {
        if (blocks.trim().isEmpty) return;
        final suggestionMatch = RegExp(
          r'\[SUGGEST_START\][\s\S]*?\[SUGGEST_END\]',
        ).firstMatch(fullContent);
        if (suggestionMatch == null) {
          fullContent = '${fullContent.trimRight()}\n\n$blocks';
          return;
        }
        fullContent =
            '${fullContent.substring(0, suggestionMatch.start).trimRight()}'
            '\n\n$blocks\n\n'
            '${fullContent.substring(suggestionMatch.start)}';
      }

      final missingFallbackBeforeRetry = !nativeToolMode
          ? missingFallbackProposalBlocks(fullContent)
          : const <String>{};
      if (!nativeToolMode &&
          _cancelGeneration?.isCompleted != true &&
          fallbackWriteTools.isNotEmpty &&
          missingFallbackBeforeRetry.isNotEmpty &&
          !AiToolChatRunner.isLikelyClarification(fullContent)) {
        final missingCdtActions = missingFallbackCdtActionNames(fullContent);
        final existingFallbackTodoCount = fallbackCreatedTodoCount(fullContent);
        final remainingFallbackTodoCount = requiredFallbackTodoCount == null
            ? null
            : requiredFallbackTodoCount > existingFallbackTodoCount
            ? requiredFallbackTodoCount - existingFallbackTodoCount
            : 0;
        final remainingFallbackFinanceDraftCount =
            requiredFallbackFinanceDraftCount == null
            ? null
            : (requiredFallbackFinanceDraftCount -
                      fallbackCreatedFinanceDraftCount(fullContent))
                  .clamp(0, requiredFallbackFinanceDraftCount)
                  .toInt();
        final missingLabels = {
          ...missingFallbackBeforeRetry.map(
            (name) => fallbackMissingProposalLabel(name, fullContent),
          ),
          ...missingCdtActions.map(
            (name) => fallbackMissingCdtActionLabel(name, fullContent),
          ),
        }.join('、');
        final retryMessages = [
          ...apiMessages,
          {'role': 'assistant', 'content': fullContent},
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
            usageSummary = ChatUsageSummary.combine(usageSummaries);
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
        latestRawModelReply = retryText;
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
                'propose_cdt_actions' => fallbackCdtBlocksForMissingActions(
                  retryText,
                  missingCdtActions,
                  remainingTodoCount: remainingFallbackTodoCount,
                ),
                'propose_finance_drafts' =>
                  fallbackFinanceBlocksForMissingCount(
                    retryText,
                    remainingDraftCount: remainingFallbackFinanceDraftCount,
                  ),
                _ => completeFallbackBlocks(retryText, start, end),
              });
            }
          }
          appendFallbackBlocks(recoveredBlocks.join('\n\n'));
          if (retryReasoning.isNotEmpty) {
            reasoningContent = retryReasoning.toString();
          }
        }
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
            availableTeams: widget.teams,
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
        availableTeams: widget.teams,
        allowedActionNames: allowedCdtActionNames,
      );
      final hasUnresolvedCountdownTeamBinding =
          (hasRequestedCountdownTeamBinding &&
              requestedCountdownTeam == null) ||
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
              ...missingFallbackCdtActionNames(fullContent),
            };
      final missingFallbackWrites = !nativeToolMode
          ? {
              ...missingFallbackProposalBlocks(fullContent),
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
              if (name != 'propose_cdt_actions' || missingFallbackCdtActions.isEmpty) fallbackMissingProposalLabel(name, fullContent), ...missingFallbackCdtActions.map((name) => fallbackMissingCdtActionLabel(name, fullContent))].join('、')}；应用没有写入缺失操作，请核对现有卡片并重试。'
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
                ? '工具调用已记录；应用没有自动修改数据。请查看调用详情和处理结果。'
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
    } catch (e) {
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
                content: useQueryTools
                    ? '工具查询过程中断；已返回的数据保留在调用记录中。'
                    : finishReason != null
                    ? '模型已结束本轮内容（finish_reason=$finishReason），但响应流未收尾；应用记录了已收到的内容，未修改本地数据。'
                    : '请求中断；应用记录了已收到的部分内容，未修改本地数据。',
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
          SnackBar(content: Text('AI回复失败: $e')),
        );
      }
    }
  }

  static const _planningConfirmationHint =
      '规划草案已显示在操作卡片中，请核对后点击“执行所选操作”保存。聊天文字确认不会保存，也不需要重新生成。';

  Future<bool> _tryRevealPendingPlanningDraft(String text) async {
    if (!AiNativeToolDefinitionBuilder.isMissingActionCardReport(text)) {
      return false;
    }
    final source = _messages.reversed
        .where(
          (message) =>
              message.role == ChatRole.assistant &&
              message.todoActions?.any(
                    (action) =>
                        action.isPlanBlockAction &&
                        !action.isAdded &&
                        !action.isIgnored,
                  ) ==
                  true,
        )
        .firstOrNull;
    final sessionId = _activeSessionId;
    if (source == null || sessionId == null) return false;
    final pending = source.todoActions!
        .where((action) => !action.isAdded && !action.isIgnored)
        .toList();
    final previous = source.copyWith(
      todoActions: source.todoActions!
          .where((action) => action.isAdded || action.isIgnored)
          .toList(),
      content: '尚未执行的操作草案已移至最新回复。',
    );
    final user = ChatMessage(
      role: ChatRole.user,
      content: text,
      usageSummary: _takePendingVoiceUsageSummary(),
    );
    final reply = ChatMessage(
      role: ChatRole.assistant,
      content: '已把尚未执行的规划操作移到这条回复下方，请核对后点击“执行所选操作”保存。',
      todoActions: pending,
    );
    setState(() {
      _messages[_messages.indexOf(source)] = previous;
      _messages.addAll([user, reply]);
      _actionRailCollapsed = false;
    });
    _inputCtrl.clear();
    // Move the same drafts; never duplicate executable actions in history.
    await ChatStorageService.saveHistory(_messages, sessionId);
    _scrollToBottom();
    return true;
  }

  Future<bool> _tryConfirmPendingPlanningDraft(String text) async {
    if (!_confirmPendingPlanningDraftPattern.hasMatch(text)) {
      return false;
    }
    final latest = _messages.reversed
        .where(
          (message) =>
              message.role == ChatRole.assistant &&
              message.content != _planningConfirmationHint,
        )
        .firstOrNull;
    if (latest?.todoActions?.any(
          (action) =>
              action.isPlanBlockAction && !action.isAdded && !action.isIgnored,
        ) !=
        true) {
      return false;
    }
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      return false;
    }
    final user = ChatMessage(
      role: ChatRole.user,
      content: text,
      usageSummary: _takePendingVoiceUsageSummary(),
    );
    final reply = ChatMessage(
      role: ChatRole.assistant,
      content: _planningConfirmationHint,
    );
    setState(() {
      _messages.addAll([user, reply]);
      _actionRailCollapsed = false;
    });
    _inputCtrl.clear();
    await ChatStorageService.addMessage(user, sessionId: sessionId);
    await ChatStorageService.addMessage(reply, sessionId: sessionId);
    _scrollToBottom();
    return true;
  }

  String _planningDraftSummary(List<AiTodoAction> actions) {
    final newTodos = actions
        .where((action) => action.newTodoTitle != null)
        .map((action) => action.newTodoTitle!)
        .toSet()
        .length;
    return '已生成 ${actions.length} 条待确认操作。'
        '${newTodos > 0 ? '其中 $newTodos 项会在执行时新建待办并关联规划。' : ''}'
        '请核对操作卡片，点击“执行所选操作”后才会保存；聊天回复“确认”不会保存。';
  }

  String _queryResultSummary(Map<String, dynamic>? result) {
    if (result == null) return '查询尚未完成。';
    if (result['ok'] == false) return '查询失败：${result['error']}';
    if (result['status'] == 'awaiting_confirmation') return '操作草案等待确认，尚未执行。';
    final summary = result['summary'];
    final count =
        result['total_count'] ??
        (summary is Map
            ? summary['transaction_count'] ?? summary['count']
            : null);
    final items = result['items'];
    return count == null
        ? '已返回只读查询结果。'
        : '查询匹配 $count 条${items is List ? '，本页返回 ${items.length} 条' : ''}。'
              '${result['has_more'] == true ? '可继续查询下一页。' : ''}';
  }

  List<ChatNativeToolCall> _buildNativeToolCallRecords({
    required List<AiChatFunctionCall> calls,
    required List<AiTodoAction> todoActions,
    required List<FinanceEntryDraft> financeDrafts,
    required List<FinanceAiAction> financeActions,
    bool interrupted = false,
  }) {
    if (calls.isEmpty) {
      return _streamingToolCalls
          .map(
            (call) => ChatNativeToolCall(
              id: call.id,
              name: call.name,
              arguments: call.arguments,
              resultSummary: interrupted
                  ? '请求已中断，参数可能不完整；本地数据未修改。'
                  : '调用参数没有完整返回；本地数据未修改。',
              argumentsComplete: false,
            ),
          )
          .toList(growable: false);
    }

    final todoCount = todoActions.where((action) => !action.isIgnored).length;
    final draftCount = financeDrafts.where((draft) => !draft.isIgnored).length;
    final financeActionCount = financeActions
        .where((action) => !action.isIgnored)
        .length;

    return calls
        .map((call) {
          final summary = switch (call.name) {
            AiSettingsNavigationService.toolName =>
              AiSettingsNavigationService.targetsFromArguments(call.arguments)
                      .isNotEmpty
                  ? '已生成设置入口卡片，点击后前往；设置未自动修改。'
                  : '未找到有效的设置入口。',
            'propose_cdt_actions' =>
              todoCount > 0
                  ? '应用解析出 $todoCount 条待确认操作草案；等待确认，本地数据未改变。'
                  : '应用未解析出有效操作；本地数据未改变。',
            'propose_finance_drafts' =>
              draftCount > 0
                  ? '应用生成 $draftCount 条记账草案；等待确认后保存。'
                  : '应用未解析出有效账单草案；本地数据未改变。',
            'propose_finance_actions' =>
              financeActionCount > 0
                  ? '应用生成 $financeActionCount 条账单修改草案；等待确认后执行。'
                  : '应用未解析出有效账单操作；本地数据未改变。',
            _ => _queryResultSummary(_queryToolResults[call.id]),
          };
          return ChatNativeToolCall(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            result: _queryToolResults[call.id],
            resultSummary: interrupted ? '$summary 请求已中断。' : summary,
          );
        })
        .toList(growable: false);
  }

  Future<void> _pickChatAttachment() async {
    if (_isLoading || _isPickingAttachment) return;
    setState(() => _isPickingAttachment = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'bmp',
          'mp3',
          'wav',
          'mp4',
          'mov',
          'webm',
          'pdf',
          'txt',
          'md',
          'csv',
          'json',
          'xml',
          'yaml',
          'yml',
        ],
      );
      if (file == null) return;
      final path = file.path ?? '';
      Uint8List? bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        // A local path can still be read later by the message builder.
      }
      if (path.isEmpty && bytes == null) {
        throw Exception('未读取到附件内容');
      }
      final extension = file.extension?.toLowerCase();
      final mimeType = switch (extension) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'bmp' => 'image/bmp',
        'jpg' || 'jpeg' => 'image/jpeg',
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        'pdf' => 'application/pdf',
        'json' => 'application/json',
        'xml' => 'application/xml',
        'yaml' || 'yml' => 'application/yaml',
        'csv' => 'text/csv',
        'md' => 'text/markdown',
        _ => 'text/plain',
      };
      final sizeBytes = bytes?.length ?? (await file.length() ?? 0);
      final attachment = ChatImageAttachment(
        path: path,
        name: file.name.isEmpty ? '附件' : file.name,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        bytes: bytes,
      );
      final maxBytes = AiMultimodalMessageBuilder.maxBytesFor(attachment.kind);
      if (sizeBytes > maxBytes) {
        throw Exception(
          '${attachment.typeLabel}过大，请选择 '
          '${(maxBytes / 1024 / 1024).round()}MB 以内的文件',
        );
      }
      setState(() {
        _pendingAttachment = attachment;
        _liveEstimatedTokens = _estimateTokensForPendingInput(
          _inputCtrl.text.trim(),
        );
      });
    } catch (error) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('选择附件失败: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingAttachment = false);
    }
  }

  Future<bool> _pasteChatImageFromClipboard() async {
    final image = await readClipboardImage();
    if (image == null) return false;

    if (_isLoading || _isPickingAttachment) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('当前操作完成后再粘贴图片')),
        );
      }
      return true;
    }
    if (_pendingAttachment != null) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('请先移除现有附件，再粘贴图片')),
        );
      }
      return true;
    }

    final maxBytes = AiMultimodalMessageBuilder.maxBytesFor(
      ChatAttachmentKind.image,
    );
    if (image.length > maxBytes) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text(
              '图片过大，请粘贴 ${(maxBytes / 1024 / 1024).round()}MB 以内的图片',
            ),
          ),
        );
      }
      return true;
    }

    if (!mounted) return true;
    setState(() {
      _pendingAttachment = ChatImageAttachment(
        path: '',
        name: image.displayName,
        mimeType: image.mimeType,
        sizeBytes: image.length,
        bytes: image.bytes,
      );
      _liveEstimatedTokens = _estimateTokensForPendingInput(
        _inputCtrl.text.trim(),
      );
    });
    return true;
  }

  Future<List<Map<String, dynamic>>> _buildApiMessagesForRequest({
    required String financeContext,
    required String habitContext,
    required String provider,
    bool nativeToolCalls = false,
    bool includeReasoningContent = false,
    bool? contextInjection,
    bool? queryTools,
  }) async {
    final baseMessages = _buildApiMessages(
      financeContext: financeContext,
      habitContext: habitContext,
      nativeToolCalls: nativeToolCalls,
      includeReasoningContent: includeReasoningContent,
      contextInjection: contextInjection,
      queryTools: queryTools,
    );
    final prepared = <Map<String, dynamic>>[];
    for (final baseMessage in baseMessages) {
      final messageId = baseMessage['_messageId']?.toString();
      final sourceMessage = messageId == null
          ? null
          : _messages.cast<ChatMessage?>().firstWhere(
              (message) => message?.id == messageId,
              orElse: () => null,
            );
      final message = Map<String, dynamic>.from(baseMessage)
        ..remove('_messageId');
      final attachment = sourceMessage?.attachment;
      if (sourceMessage?.role == ChatRole.user &&
          sourceMessage?.kind == ChatMessageKind.conversation &&
          attachment != null) {
        final text = message['content']?.toString().trim() ?? '';
        try {
          final imageInput = attachment.bytes != null
              ? ImageInputData(
                  bytes: attachment.bytes!,
                  mimeType: attachment.mimeType,
                  displayName: attachment.name,
                )
              : await readImageInput(attachment.path);
          final maxBytes = AiMultimodalMessageBuilder.maxBytesFor(
            attachment.kind,
          );
          if (imageInput.length > maxBytes) {
            throw Exception(
              '${attachment.typeLabel}过大，请选择 '
              '${(maxBytes / 1024 / 1024).round()}MB 以内的文件',
            );
          }
          message['content'] = AiMultimodalMessageBuilder.buildContent(
            text: text,
            attachment: attachment,
            bytes: imageInput.bytes,
            provider: provider,
          );
        } catch (_) {
          final isCurrentMessage =
              _messages.isNotEmpty && sourceMessage?.id == _messages.last.id;
          if (isCurrentMessage) rethrow;
          message['content'] = [
            text,
            '[历史${attachment.typeLabel}“${attachment.name}”当前不可读取，'
                '本轮仅保留文字内容。]',
          ].where((part) => part.isNotEmpty).join('\n\n');
        }
      }
      prepared.add(message);
    }
    return prepared;
  }

  Future<bool> _tryHandleExplicitFinanceText(String text) async {
    final hasPickupClue = _pickupCluePattern.hasMatch(text);
    if (hasPickupClue || !FinanceTextParser.looksLikeFinanceFormat(text)) {
      return false;
    }
    final drafts = FinanceTextParser.parse(
      text,
      source: FinanceEntrySource.import,
    );
    if (drafts.isEmpty) return false;
    final sessionId = _activeSessionId;
    if (sessionId == null) return false;

    final userMsg = ChatMessage(
      role: ChatRole.user,
      content: text,
      usageSummary: _takePendingVoiceUsageSummary(),
    );
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: _financeDraftSummary(drafts.length),
      rawContent: text,
      financeDrafts: drafts,
    );
    setState(() {
      _messages.addAll([userMsg, assistantMsg]);
      _inputCtrl.clear();
      _suggestions = [];
    });
    await ChatStorageService.addMessage(userMsg, sessionId: sessionId);
    await ChatStorageService.addMessage(assistantMsg, sessionId: sessionId);
    _scrollToBottom();
    _generateSessionTitle(sessionId: sessionId);
    return true;
  }

  String _financeDraftSummary(int count) => count == 1
      ? '已生成 1 笔待确认记账。请在下方卡片核对，点击“编辑并保存”后才会写入账本；聊天回复“确认”不会直接入账。'
      : '已生成 $count 笔待确认记账。请逐笔在下方卡片核对并点击“编辑并保存”；聊天回复“确认”不会直接入账。';

  String _appendPendingWriteConfirmationNotice({
    required String content,
    required List<AiTodoAction> todoActions,
    required List<FinanceEntryDraft> financeDrafts,
    required List<FinanceAiAction> financeActions,
  }) {
    final hasPendingTodoActions = todoActions.any(
      (action) => !action.isAdded && !action.isIgnored,
    );
    final hasPendingFinanceActions = financeActions.any(
      (action) => action.isMutation,
    );
    if (!hasPendingTodoActions &&
        financeDrafts.isEmpty &&
        !hasPendingFinanceActions) {
      return content;
    }
    if (_pendingNoticePattern.hasMatch(content)) {
      return content;
    }

    final notices = <String>[
      if (hasPendingTodoActions) '操作卡尚未写入；请核对后点击“执行所选操作”。',
      if (financeDrafts.isNotEmpty) '账单草案尚未入账；请在账单卡中点击“编辑并保存”。',
      if (hasPendingFinanceActions) '账单修改或删除尚未执行；请在对应卡片中核对并操作。',
    ];
    final notice = notices.join('\n');
    return content.trim().isEmpty ? notice : '${content.trim()}\n\n$notice';
  }

  Future<bool> _tryConfirmPendingFinanceDraft(String text) async {
    final command = text.trim().replaceAll(_punctuationStripPattern, '');
    if (!const {
      '确认',
      '确认记账',
      '确认保存',
      '确认并保存',
      '确定',
      '确定保存',
      '确定并保存',
    }.contains(command)) {
      return false;
    }

    final latestAssistant = _messages
        .where((message) => message.role == ChatRole.assistant)
        .lastOrNull;
    if (latestAssistant == null) return false;

    var drafts = latestAssistant.financeDrafts ?? const <FinanceEntryDraft>[];
    if (drafts.isEmpty) {
      drafts = FinanceTextParser.extractAssistantDrafts(
        latestAssistant.rawContent,
      );
      if (drafts.isEmpty) {
        drafts = FinanceTextParser.extractAssistantDrafts(
          latestAssistant.content,
        );
      }
    }
    drafts = drafts
        .where((draft) => !draft.isAdded && !draft.isIgnored)
        .toList(growable: false);
    if (drafts.isEmpty) return false;

    final sessionId = _activeSessionId;
    if (sessionId == null) return false;

    final legacyMessageNeedsMigration =
        latestAssistant.financeDrafts == null ||
        latestAssistant.financeDrafts!.isEmpty;
    if (legacyMessageNeedsMigration) {
      final messageIndex = _messages.indexOf(latestAssistant);
      if (messageIndex >= 0) {
        _messages[messageIndex] = latestAssistant.copyWith(
          content: FinanceTextParser.cleanAssistantContent(
            AiActionParser.cleanActionContent(latestAssistant.content),
          ),
          financeDrafts: drafts,
        );
      }
    }
    final supersededDraftsIgnored = drafts.length == 1
        ? _ignoreSupersededDateCorrectionDrafts(latestAssistant, drafts.single)
        : false;
    final historyNeedsSave =
        legacyMessageNeedsMigration || supersededDraftsIgnored;
    final userMessage = ChatMessage(
      role: ChatRole.user,
      content: text,
      usageSummary: _takePendingVoiceUsageSummary(),
    );
    final assistantMessage = ChatMessage(
      role: ChatRole.assistant,
      content: drafts.length == 1
          ? '账单草案已显示在上方确认卡中。点击“编辑并保存”，核对金额、分类和日期后保存。聊天文字确认不会直接写入账本。'
          : '当前有 ${drafts.length} 笔待确认账单，请在每笔账单卡片中分别点击“编辑并保存”核对。聊天文字确认不会直接写入账本。',
    );
    setState(() {
      _messages.addAll([userMessage, assistantMessage]);
      _inputCtrl.clear();
      _suggestions = [];
    });
    await ChatStorageService.addMessage(userMessage, sessionId: sessionId);
    await ChatStorageService.addMessage(assistantMessage, sessionId: sessionId);
    if (historyNeedsSave) await _saveHistorySilently();
    _scrollToBottom();
    return true;
  }

  bool _ignoreSupersededDateCorrectionDrafts(
    ChatMessage latestAssistant,
    FinanceEntryDraft confirmedDraft,
  ) {
    final latestIndex = _messages.indexOf(latestAssistant);
    if (latestIndex <= 0) return false;
    final previousAssistantIndex = _messages
        .take(latestIndex)
        .toList()
        .lastIndexWhere((message) => message.role == ChatRole.assistant);
    if (previousAssistantIndex < 0) return false;
    final interveningMessages = _messages.sublist(
      previousAssistantIndex + 1,
      latestIndex,
    );
    final correction = interveningMessages
        .where((message) => message.role == ChatRole.user)
        .lastOrNull;
    if (correction == null ||
        !_dateCorrectionPattern.hasMatch(correction.content)) {
      return false;
    }

    final previousAssistant = _messages[previousAssistantIndex];
    var previousDrafts =
        previousAssistant.financeDrafts ?? const <FinanceEntryDraft>[];
    if (previousDrafts.isEmpty) {
      previousDrafts = FinanceTextParser.extractAssistantDrafts(
        previousAssistant.rawContent,
      );
      if (previousDrafts.isEmpty) {
        previousDrafts = FinanceTextParser.extractAssistantDrafts(
          previousAssistant.content,
        );
      }
    }
    final matchingDrafts = previousDrafts
        .where((draft) {
          final hasDescriptor = [
            draft.merchant,
            draft.categoryName ?? draft.categoryUuid,
            draft.note,
          ].any((value) => value?.trim().isNotEmpty == true);
          return !draft.isAdded &&
              !draft.isIgnored &&
              hasDescriptor &&
              draft.transactionDate != confirmedDraft.transactionDate &&
              draft.type == confirmedDraft.type &&
              draft.amountMinor == confirmedDraft.amountMinor &&
              _sameFinanceDraftText(draft.merchant, confirmedDraft.merchant) &&
              _sameFinanceDraftText(
                draft.categoryName ?? draft.categoryUuid,
                confirmedDraft.categoryName ?? confirmedDraft.categoryUuid,
              ) &&
              _sameFinanceDraftText(
                draft.paymentMethodName ?? draft.paymentMethodUuid,
                confirmedDraft.paymentMethodName ??
                    confirmedDraft.paymentMethodUuid,
              ) &&
              _sameFinanceDraftText(draft.note, confirmedDraft.note);
        })
        .toList(growable: false);
    if (matchingDrafts.isEmpty) return false;
    for (final draft in matchingDrafts) {
      draft.isIgnored = true;
    }

    if (previousAssistant.financeDrafts == null ||
        previousAssistant.financeDrafts!.isEmpty) {
      _messages[previousAssistantIndex] = previousAssistant.copyWith(
        content: FinanceTextParser.cleanAssistantContent(
          AiActionParser.cleanActionContent(previousAssistant.content),
        ),
        financeDrafts: previousDrafts,
      );
    }
    return true;
  }

  bool _sameFinanceDraftText(String? first, String? second) =>
      (first ?? '').trim().toLowerCase() == (second ?? '').trim().toLowerCase();

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
          availableTeams: widget.teams,
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
      availableTeams: widget.teams,
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
          .map(_fallbackCdtActionLabel),
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

      String title = await AiChatService.completeChat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: [
          {
            'role': 'system',
            'content': '请根据用户的第一个问题生成一个简短的对话标题，不超过10个字，只返回标题文本，不要任何其他内容。',
          },
          {'role': 'user', 'content': firstUserMsg.content},
        ],
        provider: provider,
      );
      title = title.trim().replaceAll('"', '').replaceAll("'", '');
      if (title.length > 15) title = '${title.substring(0, 15)}...';
      if (title.isEmpty) {
        final content = firstUserMsg.content;
        title = content.substring(0, content.length > 15 ? 15 : content.length);
      }

      await ChatStorageService.updateSessionTitle(session.id, title);
      if (mounted) {
        setState(() {
          final idx = _sessions.indexWhere((s) => s.id == session.id);
          if (idx != -1) {
            _sessions[idx].title = title;
            _sessions[idx].updatedAt = DateTime.now();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('确定要清空所有聊天记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ChatStorageService.clearHistory();
      if (mounted) {
        setState(() => _messages = []);
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
