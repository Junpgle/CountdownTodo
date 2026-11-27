part of 'todo_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

mixin _TodoChatSendAttachments on _TodoChatScreenStateBase {
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
    if (result['action'] == 'save' ||
        result['action'] == 'delete' ||
        result['status'] == 'memory_disabled') {
      final message = result['message']?.toString().trim();
      if (message != null && message.isNotEmpty) return message;
    }
    if (result['ok'] == false) {
      return '查询失败：${result['error'] ?? result['message'] ?? '未知错误'}';
    }
    if (result['status'] == 'awaiting_confirmation') return '操作草案等待确认，尚未执行。';
    if (result['timezone_name'] != null && result['local_time'] != null) {
      final loc = result['location'];
      if (loc is Map) {
        final city = loc['city']?.toString().trim() ?? '';
        final region = loc['region']?.toString().trim() ?? '';
        final place = [region, city].where((s) => s.isNotEmpty).join(' · ');
        if (loc['authorized'] == true && loc['available'] == true) {
          return place.isNotEmpty
              ? '已获取当前位置（$place）与时区（${result['timezone_name']}）。'
              : '已获取当前位置与时区（${result['timezone_name']}）。';
        }
        if (loc['authorized'] == false) {
          return '已获取时间与时区（${result['timezone_name']}），位置尚未授权。';
        }
      }
      return '已获取时间与时区（${result['timezone_name']}）。';
    }
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
            AiMemoryService.toolName =>
              _queryToolResults[call.id]?['message']?.toString().trim() ??
                  '记忆已更新。',
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
      _ensureActiveSessionInList();
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
}
