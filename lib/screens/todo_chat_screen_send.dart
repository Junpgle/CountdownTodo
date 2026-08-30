part of 'todo_chat_screen.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatSend on _TodoChatScreenStateBase {
  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    // The explicit #记账 format is intentionally handled locally. This keeps
    // a simple import usable without an AI key and makes its result editable
    // immediately; natural-language finance requests still go through the
    // assistant below.
    if (await _tryHandleExplicitFinanceText(text)) return;

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

    if (apiUrl.isEmpty) apiUrl = AiChatService.defaultApiUrl;

    final userMsg = ChatMessage(
      role: ChatRole.user,
      content: text,
    );

    setState(() {
      _messages.add(userMsg);
      _streamingContent = '';
      _isLoading = true;
    });
    await ChatStorageService.addMessage(userMsg);
    _inputCtrl.clear();
    _scrollToBottom();

    _cancelGeneration = Completer<void>();

    try {
      final financeContext = await FinanceAiContextService.buildContext(
        userMessage: text,
      );
      final List<Map<String, String>> apiMessages = _buildApiMessages(
        financeContext: financeContext,
      );
      String fullContent = '';
      String reasoningContent = '';

      await for (final chunk in AiChatService.streamChat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: apiMessages,
        deepThinking: _deepThinking,
        provider: provider,
        cancelToken: _cancelGeneration,
      )) {
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
            originalText: text,
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
              todoActions: todoActions.isNotEmpty ? todoActions : null,
              financeDrafts: financeDrafts.isNotEmpty ? financeDrafts : null,
              financeActions: financeActions.isNotEmpty ? financeActions : null,
            );
            _messages.add(assistantMsg);
            _streamingContent = '';
            _streamingReasoning = '';
            _isLoading = false;
            _cancelGeneration = null;
            ChatStorageService.addMessage(assistantMsg);
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
        originalText: text,
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
        ChatStorageService.addMessage(assistantMsg);
      });
      _scrollToBottom();
      _generateSessionTitle();
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
    await ChatStorageService.addMessage(userMsg);
    await ChatStorageService.addMessage(assistantMsg);
    _scrollToBottom();
    _generateSessionTitle();
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
      await ChatStorageService.addMessage(message);
    }
    _scrollToBottom();
    _generateSessionTitle();
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
    if (lastUserMsg.content.isEmpty) return;
    // 删除最后一条助手消息（如果有）
    if (_messages.isNotEmpty && _messages.last.role == ChatRole.assistant) {
      _messages.removeLast();
    }
    _inputCtrl.text = lastUserMsg.content;
    _sendMessage();
  }

  Future<void> _generateSessionTitle() async {
    if (_messages.isEmpty) return;
    final session = _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => ChatSession(title: '新对话'),
    );
    if (session.title != '新对话') return;

    try {
      String model = _chatModel;
      String apiKey = _chatApiKey;
      String apiUrl = _chatApiUrl;

      if (model.isEmpty || apiKey.isEmpty) {
        final globalConfig = await LLMService.getConfig();
        if (globalConfig != null && globalConfig.isConfigured) {
          model = globalConfig.model;
          apiKey = globalConfig.apiKey;
          apiUrl = globalConfig.apiUrl;
        } else {
          return;
        }
      }

      if (apiUrl.isEmpty) apiUrl = AiChatService.defaultApiUrl;

      final firstUserMsg = _messages.firstWhere(
        (m) => m.role == ChatRole.user,
        orElse: () => _messages.first,
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

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('提示词设置'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
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
                await ChatStorageService.saveCustomPrompt(promptCtrl.text);
                await ChatStorageService.setPromptEnabled(enabled);
                if (mounted) {
                  setState(() {
                    _customPrompt = promptCtrl.text;
                    _promptEnabled = enabled;
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
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
