part of 'todo_chat_screen.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatSend on _TodoChatScreenStateBase {
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
    final useQueryTools =
        _smartContext && _contextMode == AiContextMode.functionCalling;
    final useContextInjection = _usesContextInjection;
    if (useQueryTools && !nativeToolMode) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text('当前模型尚未接入原生工具查询。请更换支持的模型，或在AI助手设置中切换为“智能注入”。'),
          ),
        );
      }
      return;
    }
    final sessionId = _activeSessionId;
    if (sessionId == null) return;

    var attachmentForMessage = attachment;
    if (attachment != null &&
        attachment.path.isNotEmpty &&
        !attachment.path.startsWith('data:')) {
      try {
        final persistedPath = await persistImagePath(
          attachment.path,
          'chat_attachments',
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
    );
    final requestText = userMsg.content;
    final previousUserMessage = _latestUserTextFromHistory();

    setState(() {
      _messages.add(userMsg);
      _streamingContent = '';
      _streamingReasoning = '';
      _streamingToolCalls = [];
      _queryToolResults.clear();
      _streamingFinishReason = null;
      _isLoading = true;
      _pendingAttachment = null;
    });
    await ChatStorageService.addMessage(userMsg, sessionId: sessionId);
    _inputCtrl.clear();
    _scrollToBottom();

    _cancelGeneration = Completer<void>();
    ChatUsageSummary? usageSummary;

    try {
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
              if (useQueryTools) ...AiQueryToolService.buildDefinitions(),
              ...AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
                requestText,
                previousUserMessage: previousUserMessage,
              ),
            ]
          : null;
      final allowedNativeToolNames =
          AiNativeToolDefinitionBuilder.allowedToolNames(nativeTools);
      final allowedNativeCdtActions =
          AiNativeToolDefinitionBuilder.allowedCdtActionNames(nativeTools);
      final allowedNativeFinanceActions =
          AiNativeToolDefinitionBuilder.allowedFinanceActionNames(nativeTools);
      final includeReasoningContent =
          nativeToolMode &&
          AiChatService.effectiveProvider(provider, apiUrl) == 'deepseek';
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
      String reasoningContent = '';
      final nativeToolCalls = <AiChatFunctionCall>[];
      final toolCallProgress = <int, ChatNativeToolCall>{};
      final usageSummaries = <ChatUsageSummary>[];

      Stream<AiChatStreamChunk> streamRound(
        List<Map<String, dynamic>> messages,
        List<Map<String, dynamic>> tools,
      ) => AiChatService.streamChat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
        deepThinking: _deepThinking,
        provider: provider,
        cancelToken: _cancelGeneration,
        imageCount: attachment?.kind == ChatAttachmentKind.image ? 1 : 0,
        tools: tools,
      );
      final responseStream = useQueryTools
          ? AiToolChatRunner.run(
              messages: apiMessages,
              tools: nativeTools!,
              streamRound: streamRound,
              executeRead: _createQueryToolService().execute,
              cancelToken: _cancelGeneration,
              includeReasoningContent: includeReasoningContent,
            )
          : streamRound(apiMessages, nativeTools ?? []);
      await for (final chunk in responseStream) {
        if (chunk.usageSummary != null) {
          usageSummaries.add(chunk.usageSummary!);
          usageSummary = ChatUsageSummary.combine(usageSummaries);
        }
        _queryToolResults.addAll(chunk.toolResults);
        if (chunk.finishReason != null && chunk.finishReason!.isNotEmpty) {
          if (mounted) {
            setState(() {
              _streamingFinishReason = chunk.finishReason;
            });
          }
        }
        if (chunk.reasoningContent.isNotEmpty) {
          reasoningContent += chunk.reasoningContent;
          if (mounted) {
            setState(() {
              _streamingReasoning = reasoningContent;
            });
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
          setState(() {
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
          });
          _scrollToBottom();
        }
        if (chunk.content.isNotEmpty) {
          fullContent += chunk.content;
          if (mounted) {
            setState(() {
              _streamingContent = fullContent;
            });
            _scrollToBottom();
          }
        }
      }

      final actionContent = AiNativeToolCallParser.appendToAssistantText(
        fullContent,
        nativeToolCalls,
        allowedToolNames: allowedNativeToolNames,
        allowedCdtActionNames: allowedNativeCdtActions,
        allowedFinanceActionNames: allowedNativeFinanceActions,
      );
      final rawModelReply = AiNativeToolCallParser.formatRawReply(
        fullContent,
        nativeToolCalls,
      );

      // 用户主动打断：保存已有内容为部分回复
      if (_cancelGeneration?.isCompleted == true) {
        if (fullContent.isNotEmpty ||
            reasoningContent.isNotEmpty ||
            nativeToolCalls.isNotEmpty ||
            _streamingToolCalls.isNotEmpty) {
          final existingTodoTitles = {
            for (final todo in widget.todos)
              if (todo['id'] != null)
                todo['id'].toString(): '${todo['title'] ?? ''}',
          };
          final existingScheduleTitles = {
            for (final schedule in _fixedSchedules) schedule.id: schedule.title,
          };
          final todoActions = AiActionParser.extractTodoActions(
            actionContent,
            originalText: requestText,
            existingTodoTitles: existingTodoTitles,
            existingScheduleTitles: existingScheduleTitles,
          );
          final financeDrafts = FinanceTextParser.extractAssistantDrafts(
            actionContent,
          );
          final financeActions = FinanceTextParser.extractAssistantActions(
            actionContent,
          );
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
          final interruptedContent = financeDrafts.isNotEmpty
              ? _financeDraftSummary(financeDrafts.length)
              : cleanContent.isNotEmpty
              ? cleanContent
              : todoActions.isNotEmpty
              ? '已生成待确认操作草案，请核对后添加。'
              : financeActions.isNotEmpty
              ? '已生成账单操作草案，请在确认卡中核对。'
              : nativeToolCalls.isNotEmpty || _streamingToolCalls.isNotEmpty
              ? '工具调用已记录；应用没有自动修改数据。请查看调用详情和处理结果。'
              : cleanContent;
          final finishReasonNote = _streamingFinishReason == null
              ? ''
              : '\n\n模型结束原因：$_streamingFinishReason；响应流收尾前已中断。';
          setState(() {
            final assistantMsg = ChatMessage(
              role: ChatRole.assistant,
              content: '$interruptedContent$finishReasonNote\n\n*(已中断)*',
              rawContent: rawModelReply,
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

      final existingTodoTitles = {
        for (final todo in widget.todos)
          if (todo['id'] != null)
            todo['id'].toString(): '${todo['title'] ?? ''}',
      };
      final existingScheduleTitles = {
        for (final schedule in _fixedSchedules) schedule.id: schedule.title,
      };
      final todoActions = AiActionParser.extractTodoActions(
        actionContent,
        originalText: requestText,
        existingTodoTitles: existingTodoTitles,
        existingScheduleTitles: existingScheduleTitles,
      );
      final inlineSuggestions = AiActionParser.extractSuggestions(
        actionContent,
      );
      final financeDrafts = FinanceTextParser.extractAssistantDrafts(
        actionContent,
      );
      final financeActions = FinanceTextParser.extractAssistantActions(
        actionContent,
      );
      final nativeToolCallRecords = _buildNativeToolCallRecords(
        calls: nativeToolCalls,
        todoActions: todoActions,
        financeDrafts: financeDrafts,
        financeActions: financeActions,
      );
      final cleanContent = FinanceTextParser.cleanAssistantContent(
        AiActionParser.cleanActionContent(actionContent),
      );
      final assistantContent = financeDrafts.isNotEmpty
          ? _financeDraftSummary(financeDrafts.length)
          : cleanContent.isNotEmpty
          ? cleanContent
          : todoActions.isNotEmpty
          ? '已生成待确认操作草案，请核对后添加。'
          : financeActions.isNotEmpty
          ? '已生成账单操作草案，请在确认卡中核对。'
          : nativeToolCalls.isNotEmpty
          ? '工具调用已记录；应用没有自动修改数据。请查看调用详情和处理结果。'
          : cleanContent;

      final assistantMsg = ChatMessage(
        role: ChatRole.assistant,
        content: assistantContent,
        rawContent: rawModelReply,
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
        _suggestions = inlineSuggestions.isNotEmpty
            ? inlineSuggestions
            : _getSmartSuggestions();
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
    final hasPickupClue = RegExp(r'取餐|取件|取货|餐号|取单号|取餐码|取件码|外卖|快递')
        .hasMatch(text);
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

    final userMsg = ChatMessage(role: ChatRole.user, content: text);
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: _financeDraftSummary(drafts.length),
      rawContent: text,
      financeDrafts: drafts,
    );
    setState(() {
      _messages.addAll([userMsg, assistantMsg]);
      _inputCtrl.clear();
      _suggestions = _getSmartSuggestions();
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

  Future<bool> _tryConfirmPendingFinanceDraft(String text) async {
    final command = text
        .trim()
        .replaceAll(RegExp(r'[\s，。！？、,.!?]'), '');
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
        ? _ignoreSupersededDateCorrectionDrafts(
            latestAssistant,
            drafts.single,
          )
        : false;
    final historyNeedsSave =
        legacyMessageNeedsMigration || supersededDraftsIgnored;
    final userMessage = ChatMessage(role: ChatRole.user, content: text);
    final assistantMessage = ChatMessage(
      role: ChatRole.assistant,
      content: drafts.length == 1
          ? '账单草案已显示在上方确认卡中。点击“编辑并保存”，核对金额、分类和日期后保存。聊天文字确认不会直接写入账本。'
          : '当前有 ${drafts.length} 笔待确认账单，请在每笔账单卡片中分别点击“编辑并保存”核对。聊天文字确认不会直接写入账本。',
    );
    setState(() {
      _messages.addAll([userMessage, assistantMessage]);
      _inputCtrl.clear();
      _suggestions = _getSmartSuggestions();
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
        !RegExp(
          r'(?:\d{2,4}\s*年|\d{1,2}\s*月|\d{1,2}\s*(?:日|号)|\d{4}[-/.]\d{1,2})',
        ).hasMatch(correction.content)) {
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
    final matchingDrafts = previousDrafts.where((draft) {
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
            confirmedDraft.paymentMethodName ?? confirmedDraft.paymentMethodUuid,
          ) &&
          _sameFinanceDraftText(draft.note, confirmedDraft.note);
    }).toList(growable: false);
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
      (first ?? '').trim().toLowerCase() ==
      (second ?? '').trim().toLowerCase();

  Future<void> _copyManualPromptFromInput() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final financeContext = _usesContextInjection
        ? await FinanceAiContextService.buildContext(
            userMessage: text,
            conversationContext: _recentConversationTextForContext(),
            previousUserMessage: _latestUserTextFromHistory(),
            dateRangeOverride: _financeContextDateRangeOverride(),
          )
        : '';
    final habitContext = _usesContextInjection
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
          _contextMode == AiContextMode.functionCalling
              ? '已复制对话提示词。外部AI无法调用App查询工具；需要附带数据时请切换为“智能注入”。'
              : '已复制完整提示词，可粘贴到外部AI',
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
          width: MediaQuery.of(ctx).size.width * 0.86,
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
    final existingTodoTitles = {
      for (final todo in widget.todos)
        if (todo['id'] != null) todo['id'].toString(): '${todo['title'] ?? ''}',
    };
    final existingScheduleTitles = {
      for (final schedule in _fixedSchedules) schedule.id: schedule.title,
    };
    final todoActions = AiActionParser.extractTodoActions(
      fullContent,
      originalText: originalText,
      existingTodoTitles: existingTodoTitles,
      existingScheduleTitles: existingScheduleTitles,
    );
    final inlineSuggestions = AiActionParser.extractSuggestions(fullContent);
    final financeDrafts = FinanceTextParser.extractAssistantDrafts(fullContent);
    final financeActions = FinanceTextParser.extractAssistantActions(
      fullContent,
    );
    final cleanContent = FinanceTextParser.cleanAssistantContent(
      AiActionParser.cleanActionContent(fullContent),
    );

    final newMessages = <ChatMessage>[];
    if (originalText.isNotEmpty && _lastUserContent() != originalText) {
      newMessages.add(ChatMessage(role: ChatRole.user, content: originalText));
    }
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: financeDrafts.isNotEmpty
          ? _financeDraftSummary(financeDrafts.length)
          : cleanContent.isEmpty
          ? financeActions.isNotEmpty
              ? '已生成账单操作草案，请在确认卡中核对。'
              : fullContent
          : cleanContent,
      rawContent: fullContent,
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
      _suggestions = inlineSuggestions.isNotEmpty
          ? inlineSuggestions
          : _getSmartSuggestions();
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
    final promptCtrl = TextEditingController(text: _customPrompt);
    bool enabled = _promptEnabled;
    bool smartContext = _smartContext;
    AiContextMode contextMode = _contextMode;
    bool showContextPreview = _showInjectedContextPreview;
    bool injectMoreContext = _injectMoreContext;
    bool deepThinking = _deepThinking;

    Future<void> persistAssistantSettings() async {
      await ChatStorageService.saveCustomPrompt(promptCtrl.text);
      await ChatStorageService.setPromptEnabled(enabled);
      await Future.wait([
        ChatStorageService.setSmartContextEnabled(smartContext),
        ChatStorageService.setContextMode(contextMode),
        ChatStorageService.setShowContextPreview(showContextPreview),
        ChatStorageService.setInjectMoreContext(injectMoreContext),
        ChatStorageService.setDeepThinkingEnabled(deepThinking),
      ]);
      if (!mounted) return;
      setState(() {
        _customPrompt = promptCtrl.text;
        _promptEnabled = enabled;
        _smartContext = smartContext;
        _contextMode = contextMode;
        _showInjectedContextPreview = showContextPreview;
        _injectMoreContext = injectMoreContext;
        _deepThinking = deepThinking;
        _liveSmartContextPreview = _buildSmartContextPreview(
          _inputCtrl.text.trim(),
        );
        _liveActionProtocolPreview = _buildActionProtocolPreview(
          _inputCtrl.text.trim(),
        );
        _liveEstimatedTokens = _estimateTokensForPendingInput(
          _inputCtrl.text.trim(),
        );
      });
    }

    await showAppDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AI 助手设置'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '这里管理助手的行为、上下文与协议。模型、API Key 和服务商在独立的“模型与 API 配置”中管理。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '行为与上下文',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('智能上下文'),
                    subtitle: const Text('允许助手通过所选模式读取待办、课程、账单、习惯等业务数据'),
                    value: smartContext,
                    onChanged: (value) =>
                        setDialogState(() => smartContext = value),
                  ),
                  AiContextModeSelector(
                    value: contextMode,
                    onChanged: (value) =>
                        setDialogState(() => contextMode = value),
                  ),
                  const SizedBox(height: 8),
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('在输入区显示注入预览'),
                    subtitle: const Text('关闭只会隐藏 UI 详情，不会停止上下文注入'),
                    value: showContextPreview,
                    onChanged:
                        smartContext &&
                            contextMode == AiContextMode.smartContextInjection
                        ? (value) =>
                              setDialogState(() => showContextPreview = value)
                        : null,
                  ),
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('默认扩展上下文范围'),
                    subtitle: const Text('相关日期问题默认查看未来 30 天'),
                    value: injectMoreContext,
                    onChanged:
                        smartContext &&
                            contextMode == AiContextMode.smartContextInjection
                        ? (value) =>
                              setDialogState(() => injectMoreContext = value)
                        : null,
                  ),
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('默认开启深度思考'),
                    subtitle: const Text('模型支持时附带 thinking 参数'),
                    value: deepThinking,
                    onChanged: (value) =>
                        setDialogState(() => deepThinking = value),
                  ),
                  const Divider(height: 24),
                  const Text(
                    '动作与上下文协议',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'CDT Actions v2 · Smart Context v2\n'
                      '新回复使用带版本的动作信封；仍可读取旧版 ACTION 数组和历史聊天记录。',
                      style: TextStyle(fontSize: 12.5, height: 1.45),
                    ),
                  ),
                  const Divider(height: 24),
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用自定义提示词'),
                    subtitle: const Text('关闭后将使用默认提示词'),
                    value: enabled,
                    onChanged: (val) {
                      setDialogState(() => enabled = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '提示词内容',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: promptCtrl,
                    maxLines: 12,
                    minLines: 6,
                    enabled: enabled,
                    decoration: InputDecoration(
                      hintText: '输入自定义提示词...\n\n可用变量：\n{now} - 当前时间\n{todos} - 待办清单\n固定日程、规划块等上下文会按当前问题自动注入',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          promptCtrl.text = ChatStorageService.defaultPrompt;
                          setDialogState(() => enabled = true);
                        },
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复默认'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          _showPromptPreview(promptCtrl.text, enabled);
                        },
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('预览'),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.hub_rounded),
                    title: const Text('模型与 API 配置'),
                    subtitle: const Text('服务商、API Key、文本模型与多模态模型'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await persistAssistantSettings();
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (mounted) unawaited(_openLlmConfigPage());
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await persistAssistantSettings();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    promptCtrl.dispose();
  }

  void _showPromptPreview(String prompt, bool enabled) {
    final resolvedPrompt = AiTodoContextBuilder.buildPromptPreview(
      customPrompt: prompt,
      promptEnabled: enabled,
      todos: widget.todos,
      todoGroups: widget.todoGroups,
    );

    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示词预览'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              resolvedPrompt,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
