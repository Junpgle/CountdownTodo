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
    if (attachment == null && await _tryHandleExplicitFinanceText(text)) return;

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
        final goToSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('未配置大模型'),
            content: const Text(
              '可以先配置API地址和密钥，也可以复制完整提示词到外部AI，稍后把回复粘贴回来识别。',
            ),
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
            ScaffoldMessenger.of(context).showSnackBar(
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先配置支持该输入的多模态模型')),
          );
        }
        return;
      }
    }

    if (apiUrl.isEmpty) apiUrl = AiChatService.defaultApiUrl;
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
      content: text.isEmpty
          ? switch (attachment?.kind) {
              ChatAttachmentKind.image => '请分析图片内容，并提取重要信息、待办与建议。',
              ChatAttachmentKind.audio => '请理解这段音频，并提取重要信息、待办与建议。',
              ChatAttachmentKind.video => '请分析这段视频，并提取重要信息、待办与建议。',
              ChatAttachmentKind.document => '请阅读这份文件，并提取重要信息、待办与建议。',
              null => '',
            }
          : text,
      attachment: attachmentForMessage,
    );
    final requestText = userMsg.content;

    setState(() {
      _messages.add(userMsg);
      _streamingContent = '';
      _streamingReasoning = '';
      _isLoading = true;
      _pendingAttachment = null;
    });
    await ChatStorageService.addMessage(userMsg, sessionId: sessionId);
    _inputCtrl.clear();
    _scrollToBottom();

    _cancelGeneration = Completer<void>();

    try {
      final financeContext = await FinanceAiContextService.buildContext(
        userMessage: requestText,
      );
      final List<Map<String, dynamic>> apiMessages =
          await _buildApiMessagesForRequest(
        financeContext: financeContext,
        provider: provider,
      );
      String fullContent = '';
      String reasoningContent = '';
      ChatUsageSummary? usageSummary;

      await for (final chunk in AiChatService.streamChat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: apiMessages,
        deepThinking: _deepThinking,
        provider: provider,
        cancelToken: _cancelGeneration,
        imageCount: attachment?.kind == ChatAttachmentKind.image ? 1 : 0,
      )) {
        if (chunk.usageSummary != null) {
          usageSummary = chunk.usageSummary;
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

      // 用户主动打断：保存已有内容为部分回复
      if (_cancelGeneration?.isCompleted == true) {
        if (fullContent.isNotEmpty || reasoningContent.isNotEmpty) {
          final existingTodoTitles = {
            for (final todo in widget.todos)
              if (todo['id'] != null)
                todo['id'].toString(): '${todo['title'] ?? ''}',
          };
          final existingScheduleTitles = {
            for (final schedule in _fixedSchedules) schedule.id: schedule.title,
          };
          final todoActions = AiActionParser.extractTodoActions(
            fullContent,
            originalText: requestText,
            existingTodoTitles: existingTodoTitles,
            existingScheduleTitles: existingScheduleTitles,
          );
          final financeDrafts = FinanceTextParser.extractAssistantDrafts(
            fullContent,
          );
          final financeActions = FinanceTextParser.extractAssistantActions(
            fullContent,
          );
          final cleanContent = FinanceTextParser.cleanAssistantContent(
            AiActionParser.cleanActionContent(fullContent),
          );
          setState(() {
            final assistantMsg = ChatMessage(
              role: ChatRole.assistant,
              content:
                  '${cleanContent.isEmpty && (financeDrafts.isNotEmpty || financeActions.isNotEmpty) ? financeDrafts.isNotEmpty ? '已生成记账草案，请核对后编辑并保存。' : '已生成账单操作草案，请在确认卡中核对。' : cleanContent}\n\n*(已中断)*',
              rawContent: fullContent,
              reasoningContent: reasoningContent,
              smartContext: _lastRequestSmartContext,
              usageSummary: usageSummary,
              todoActions: todoActions.isNotEmpty ? todoActions : null,
              financeDrafts: financeDrafts.isNotEmpty ? financeDrafts : null,
              financeActions: financeActions.isNotEmpty ? financeActions : null,
            );
            _messages.add(assistantMsg);
            _streamingContent = '';
            _streamingReasoning = '';
            _isLoading = false;
            _cancelGeneration = null;
            ChatStorageService.addMessage(assistantMsg, sessionId: sessionId);
          });
        } else {
          setState(() {
            _streamingContent = '';
            _streamingReasoning = '';
            _isLoading = false;
            _cancelGeneration = null;
          });
        }
        _scrollToBottom();
        return;
      }

      if (fullContent.isEmpty && reasoningContent.isEmpty) {
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
        fullContent,
        originalText: requestText,
        existingTodoTitles: existingTodoTitles,
        existingScheduleTitles: existingScheduleTitles,
      );
      final inlineSuggestions = AiActionParser.extractSuggestions(fullContent);
      final financeDrafts = FinanceTextParser.extractAssistantDrafts(
        fullContent,
      );
      final financeActions = FinanceTextParser.extractAssistantActions(
        fullContent,
      );
      final cleanContent = FinanceTextParser.cleanAssistantContent(
        AiActionParser.cleanActionContent(fullContent),
      );

      setState(() {
        final assistantMsg = ChatMessage(
          role: ChatRole.assistant,
          content: cleanContent.isEmpty &&
                  (financeDrafts.isNotEmpty || financeActions.isNotEmpty)
              ? financeDrafts.isNotEmpty
                  ? '已生成记账草案，请核对后编辑并保存。'
                  : '已生成账单操作草案，请在确认卡中核对。'
              : cleanContent,
          rawContent: fullContent,
          reasoningContent: reasoningContent,
          smartContext: _lastRequestSmartContext,
          usageSummary: usageSummary,
          todoActions: todoActions.isNotEmpty ? todoActions : null,
          financeDrafts: financeDrafts.isNotEmpty ? financeDrafts : null,
          financeActions: financeActions.isNotEmpty ? financeActions : null,
        );

        _messages.add(assistantMsg);
        _streamingContent = '';
        _streamingReasoning = '';
        _isLoading = false;
        _cancelGeneration = null;
        _suggestions = inlineSuggestions.isNotEmpty
            ? inlineSuggestions
            : _getSmartSuggestions();
        if (todoActions.isNotEmpty) {
          _actionRailCollapsed = false;
        }
        ChatStorageService.addMessage(assistantMsg, sessionId: sessionId);
      });
      _scrollToBottom();
      _generateSessionTitle(sessionId: sessionId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _streamingContent = '';
          _isLoading = false;
          _cancelGeneration = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI回复失败: $e')),
        );
      }
    }
  }

  Future<void> _pickChatAttachment() async {
    if (_isLoading || _isPickingAttachment) return;
    setState(() => _isPickingAttachment = true);
    try {
      final result = await FilePicker.platform.pickFiles(
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
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path ?? '';
      final bytes = file.bytes;
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
      final attachment = ChatImageAttachment(
        path: path,
        name: file.name.isEmpty ? '附件' : file.name,
        mimeType: mimeType,
        sizeBytes: file.size,
        bytes: bytes,
      );
      final maxBytes = AiMultimodalMessageBuilder.maxBytesFor(attachment.kind);
      if (file.size > maxBytes) {
        throw Exception(
          '${attachment.typeLabel}过大，请选择 '
          '${(maxBytes / 1024 / 1024).round()}MB 以内的文件',
        );
      }
      setState(() {
        _pendingAttachment = attachment;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择附件失败: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingAttachment = false);
    }
  }

  Future<List<Map<String, dynamic>>> _buildApiMessagesForRequest({
    required String financeContext,
    required String provider,
  }) async {
    final baseMessages = _buildApiMessages(financeContext: financeContext);
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
          final maxBytes =
              AiMultimodalMessageBuilder.maxBytesFor(attachment.kind);
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
    final hasPickupClue = RegExp(
      r'取餐|取件|取货|餐号|取单号|取餐码|取件码|外卖|快递',
    ).hasMatch(text);
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
      content: drafts.length == 1
          ? '已识别为一笔记账草案，请核对后编辑并保存。'
          : '已识别为 ${drafts.length} 笔记账草案，请逐笔核对后保存。',
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

  Future<void> _copyManualPromptFromInput() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final financeContext = await FinanceAiContextService.buildContext(
      userMessage: text,
    );
    final apiMessages = _buildApiMessages(
      pendingUserText: text,
      financeContext: financeContext,
    );
    final manualPrompt =
        AiTodoContextBuilder.buildManualCopyPrompt(apiMessages);
    _pendingManualOriginalText = text;
    _pendingManualSmartContext = _lastRequestSmartContext;
    await Clipboard.setData(ClipboardData(text: manualPrompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制完整提示词，可粘贴到外部AI')),
    );
  }

  Future<void> _pasteManualReplyFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final replyCtrl = TextEditingController(text: data?.text?.trim() ?? '');

    final reply = await showDialog<String>(
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
    final financeActions =
        FinanceTextParser.extractAssistantActions(fullContent);
    final cleanContent = FinanceTextParser.cleanAssistantContent(
      AiActionParser.cleanActionContent(fullContent),
    );

    final newMessages = <ChatMessage>[];
    if (originalText.isNotEmpty && _lastUserContent() != originalText) {
      newMessages.add(ChatMessage(role: ChatRole.user, content: originalText));
    }
    final assistantMsg = ChatMessage(
      role: ChatRole.assistant,
      content: cleanContent.isEmpty
          ? financeDrafts.isNotEmpty
              ? '已生成记账草案，请核对后编辑并保存。'
              : financeActions.isNotEmpty
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

    setState(() {
      _messages.addAll(newMessages);
      _streamingContent = '';
      _streamingReasoning = '';
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
          {
            'role': 'user',
            'content': firstUserMsg.content,
          },
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
    final confirmed = await showDialog<bool>(
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
    bool showContextPreview = _showInjectedContextPreview;
    bool injectMoreContext = _injectMoreContext;
    bool deepThinking = _deepThinking;

    Future<void> persistAssistantSettings() async {
      await ChatStorageService.saveCustomPrompt(promptCtrl.text);
      await ChatStorageService.setPromptEnabled(enabled);
      await Future.wait([
        ChatStorageService.setSmartContextEnabled(smartContext),
        ChatStorageService.setShowContextPreview(showContextPreview),
        ChatStorageService.setInjectMoreContext(injectMoreContext),
        ChatStorageService.setDeepThinkingEnabled(deepThinking),
      ]);
      if (!mounted) return;
      setState(() {
        _customPrompt = promptCtrl.text;
        _promptEnabled = enabled;
        _smartContext = smartContext;
        _showInjectedContextPreview = showContextPreview;
        _injectMoreContext = injectMoreContext;
        _deepThinking = deepThinking;
        _liveSmartContextPreview =
            _buildSmartContextPreview(_inputCtrl.text.trim());
        _liveActionProtocolPreview =
            _buildActionProtocolPreview(_inputCtrl.text.trim());
        _liveEstimatedTokens =
            _estimateTokensForPendingInput(_inputCtrl.text.trim());
      });
    }

    await showDialog(
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
                    subtitle: const Text('按当前问题注入待办、日程、规划、账单等只读数据'),
                    value: smartContext,
                    onChanged: (value) =>
                        setDialogState(() => smartContext = value),
                  ),
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('在输入区显示注入预览'),
                    subtitle: const Text('关闭只会隐藏 UI 详情，不会停止上下文注入'),
                    value: showContextPreview,
                    onChanged: smartContext
                        ? (value) => setDialogState(
                              () => showContextPreview = value,
                            )
                        : null,
                  ),
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('默认扩展上下文范围'),
                    subtitle: const Text('相关日期问题默认查看未来 30 天'),
                    value: injectMoreContext,
                    onChanged: smartContext
                        ? (value) => setDialogState(
                              () => injectMoreContext = value,
                            )
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
                      hintText:
                          '输入自定义提示词...\n\n可用变量：\n{now} - 当前时间\n{todos} - 待办清单\n固定日程、规划块等上下文会按当前问题自动注入',
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
                          _showPromptPreview(
                            promptCtrl.text,
                            enabled,
                          );
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

    showDialog(
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
