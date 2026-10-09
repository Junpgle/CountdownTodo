part of 'todo_chat_screen.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatMessages on _TodoChatScreenStateBase {
  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    final isUser = msg.role == ChatRole.user;
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);
    final colorScheme = Theme.of(context).colorScheme;
    final maxBubbleWidth = MediaQuery.of(context).size.width >= 900
        ? (isUser ? 560.0 : 720.0)
        : MediaQuery.of(context).size.width * (isUser ? 0.82 : 0.9);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(
                  Icons.smart_toy_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isUser)
                    AiChatThinkingPanel(
                      reasoning: msg.reasoningContent,
                      calls: msg.nativeToolCalls ?? const [],
                      hasReply: msg.content.trim().isNotEmpty,
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? colorScheme.primary
                          : isDark
                          ? colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            )
                          : colorScheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.035),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: isUser
                          ? null
                          : Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.55,
                              ),
                              width: 0.5,
                            ),
                    ),
                    child: isUser
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.attachment != null)
                                _buildChatAttachmentPreview(msg.attachment!),
                              if (msg.content.isNotEmpty)
                                Text(
                                  msg.content,
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              if (msg.usageSummary != null)
                                _buildUsageSummaryFooter(
                                  msg.usageSummary!,
                                  isVoice: msg.usageSummary!.model ==
                                      MimoAsrService.model,
                                  foregroundColor: colorScheme.onPrimary,
                                ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.recognition != null)
                                _buildRecognitionMessage(msg, isDark)
                              else
                                AiChatMarkdown(data: msg.content),
                              if (msg.usageSummary != null)
                                _buildUsageSummaryFooter(msg.usageSummary!),
                              if (msg.smartContext.trim().isNotEmpty)
                                _buildSmartContextPanel(msg.smartContext),
                            ],
                          ),
                  ),
                  if (!_shouldDetachActions &&
                      msg.todoActions != null &&
                      msg.todoActions!.isNotEmpty)
                    _buildMessageTodoActions(msg, isDark),
                  if (msg.financeDrafts != null &&
                      msg.financeDrafts!.isNotEmpty)
                    _buildMessageFinanceDrafts(msg, isDark),
                  if (msg.financeActions != null &&
                      msg.financeActions!.isNotEmpty)
                    _buildMessageFinanceActions(msg, isDark),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w300,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ),
                        if (!isUser) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _showRawReplyDialog(msg),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.data_object_rounded,
                                    size: 12,
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.82,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '原始回复',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.88,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 6),
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: colorScheme.secondary.withValues(alpha: 0.1),
                child: Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: colorScheme.secondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStreamingBubble(bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleContent = AiActionParser.cleanActionContent(
      FinanceTextParser.cleanStreamingAssistantContent(_streamingContent),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _PulseAvatar(
            child: CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.smart_toy_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width >= 900
                    ? 720
                    : MediaQuery.of(context).size.width * 0.9,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AiChatThinkingPanel(
                    reasoning: _streamingReasoning,
                    calls: _streamingToolCalls,
                    isStreaming: true,
                    hasReply: visibleContent.trim().isNotEmpty,
                    finishReason: _streamingFinishReason,
                  ),
                  if (visibleContent.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? colorScheme.surfaceContainerHighest.withValues(
                                alpha: 0.4,
                              )
                            : colorScheme.surface,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                          width: 0.5,
                        ),
                      ),
                      child: AiChatMarkdown(data: visibleContent),
                    )
                  else if (_streamingReasoning.isEmpty &&
                      _streamingToolCalls.isEmpty)
                    const _ThinkingLoader(),
                  if (_streamingFinishReason != null &&
                      _streamingToolCalls.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '模型已结束本轮内容（$_streamingFinishReason），正在等待响应流收尾。',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (_lastRequestSmartContext.trim().isNotEmpty)
                    _buildSmartContextPanel(_lastRequestSmartContext),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartContextPanel(String smartContext) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: ExpansionTile(
        dense: true,
        leading: Icon(
          Icons.dataset_outlined,
          size: 18,
          color: colorScheme.secondary,
        ),
        title: Text(
          '本轮发送给 AI 的上下文',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${smartContext.length} 字符 · 展开查看具体数据',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                smartContext,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatAttachmentPreview(
    ChatImageAttachment attachment, {
    bool compact = false,
  }) {
    final width = compact ? 64.0 : 180.0;
    final height = compact ? 52.0 : 132.0;
    final scheme = Theme.of(context).colorScheme;
    final Widget preview;
    if (attachment.kind == ChatAttachmentKind.image) {
      preview = attachment.bytes != null
          ? Image.memory(
              attachment.bytes!,
              width: width,
              height: height,
              fit: BoxFit.cover,
            )
          : attachment.path.isNotEmpty && localImageExists(attachment.path)
          ? localImageWidget(
              attachment.path,
              width: width,
              height: height,
              fit: BoxFit.cover,
            )
          : Container(
              width: width,
              height: compact ? 52 : 72,
              alignment: Alignment.center,
              color: Colors.black.withValues(alpha: 0.08),
              child: const Icon(Icons.image_not_supported_outlined),
            );
    } else {
      final icon = switch (attachment.kind) {
        ChatAttachmentKind.audio => Icons.audio_file_rounded,
        ChatAttachmentKind.video => Icons.video_file_rounded,
        ChatAttachmentKind.document => Icons.description_rounded,
        ChatAttachmentKind.image => Icons.image_rounded,
      };
      final size = attachment.sizeBytes;
      final sizeLabel = size == null
          ? ''
          : size >= 1024 * 1024
          ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
          : '${(size / 1024).ceil()} KB';
      preview = Container(
        width: compact ? 180 : 260,
        constraints: BoxConstraints(minHeight: compact ? 52 : 64),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: scheme.primary, size: compact ? 22 : 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: compact ? 11 : 13,
                    ),
                  ),
                  Text(
                    [
                      attachment.typeLabel,
                      sizeLabel,
                    ].where((item) => item.isNotEmpty).join(' · '),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: preview),
    );
  }

  Widget _buildUsageSummaryFooter(
    ChatUsageSummary usage, {
    bool isVoice = false,
    Color? foregroundColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = foregroundColor ?? scheme.onSurfaceVariant;
    final parts = <String>[];
    if (usage.costMicros != null) {
      parts.add(
        '${isVoice ? '语音识别' : '本次花费'} '
        '${AiUsageCostService.formatMicros(usage.costMicros!)}',
      );
    } else {
      parts.add(isVoice ? '语音识别费用待定价' : '本次费用暂无可用价格');
    }
    if (isVoice) {
      parts.add(
        usage.audioSeconds > 0 ? '录音 ${usage.audioSeconds} 秒' : '录音时长未返回',
      );
    } else if (usage.totalTokens > 0) {
      parts.add('${usage.totalTokens} tokens');
    }
    if (usage.calls > 1) parts.add('${usage.calls} 次调用');
    if (usage.unpricedCalls > 0 && usage.costMicros != null) {
      parts.add('含 ${usage.unpricedCalls} 次未定价');
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.only(top: 7),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: (foregroundColor ?? scheme.outlineVariant)
                .withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.toll_rounded,
            size: 12,
            color: color.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecognitionMessage(ChatMessage msg, bool isDark) {
    final info = msg.recognition!;
    final scheme = Theme.of(context).colorScheme;
    final isProcessing = info.status == ChatRecognitionStatus.processing;
    final isFailed = info.status == ChatRecognitionStatus.failed;
    final statusColor = isProcessing
        ? scheme.tertiary
        : isFailed
        ? scheme.error
        : scheme.primary;
    final statusLabel = isProcessing
        ? '正在识别'
        : isFailed
        ? '识别失败'
        : '识别完成';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isProcessing
                  ? Icons.auto_awesome_rounded
                  : isFailed
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color: statusColor,
            ),
            const SizedBox(width: 6),
            Text(
              '${info.recognizer} · $statusLabel',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (isProcessing) ...[
              const Spacer(),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: statusColor,
                ),
              ),
            ],
          ],
        ),
        if (msg.content.isNotEmpty) ...[
          const SizedBox(height: 7),
          AiChatMarkdown(data: msg.content),
        ],
        if (info.todoResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: info.todoResults.asMap().entries.map((entry) {
                final result = entry.value;
                final title = (result['title'] ?? result['content'] ?? '')
                    .toString()
                    .trim();
                final detail = (result['remark'] ?? result['notes'] ?? '')
                    .toString()
                    .trim();
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == info.todoResults.length - 1 ? 0 : 5,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.key + 1}.',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          detail.isEmpty ? title : '$title · $detail',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        if (info.suggestions.isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(
            '建议下一步',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: info.suggestions.map((suggestion) {
              return ActionChip(
                label: Text(suggestion),
                onPressed: () {
                  _inputCtrl
                    ..text = suggestion
                    ..selection = TextSelection.collapsed(
                      offset: suggestion.length,
                    );
                },
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useFloating = floatingBottomBarShouldFloat(context);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final content = Container(
      key: _inputKey,
      padding: useFloating
          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
          : const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: useFloating
          ? null
          : BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.95),
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!keyboardVisible &&
                _usesContextInjection &&
                _inputHasText &&
                (_liveSmartContextPreview.isNotEmpty ||
                    _liveActionProtocolPreview.isNotEmpty)) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '智能上下文',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _injectMoreContext = !_injectMoreContext;
                              unawaited(
                                ChatStorageService.setInjectMoreContext(
                                  _injectMoreContext,
                                ),
                              );
                              _liveSmartContextPreview =
                                  _buildSmartContextPreview(
                                    _inputCtrl.text.trim(),
                                  );
                              _liveActionProtocolPreview =
                                  _buildActionProtocolPreview(
                                    _inputCtrl.text.trim(),
                                  );
                              _liveEstimatedTokens =
                                  _estimateTokensForPendingInput(
                                    _inputCtrl.text.trim(),
                                  );
                            });
                          },
                          style: TextButton.styleFrom(
                            backgroundBuilder: _keepTodoChatButtonBackground,
                            backgroundColor: Colors.transparent,
                            minimumSize: const Size(0, 22),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                          ),
                          child: Text(
                            _injectMoreContext ? '注入更多: 开' : '注入更多',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _pickCustomInjectRange,
                          style: TextButton.styleFrom(
                            backgroundBuilder: _keepTodoChatButtonBackground,
                            backgroundColor: Colors.transparent,
                            minimumSize: const Size(0, 22),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                          ),
                          child: Text(
                            _useCustomInjectRange ? '自定义注入: 开' : '自定义注入',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_injectMoreContext)
                      Text(
                        '已扩大到未来30天范围',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    if (_useCustomInjectRange &&
                        _customInjectStart != null &&
                        _customInjectEnd != null)
                      Text(
                        '自定义范围: ${DateFormat('yyyy-MM-dd').format(_customInjectStart!)} 至 ${DateFormat('yyyy-MM-dd').format(_customInjectEnd!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (_showInjectedContextPreview) ...[
                      if (_liveSmartContextPreview.isNotEmpty)
                        SelectableText(
                          _liveSmartContextPreview,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      if (_liveActionProtocolPreview.isNotEmpty)
                        SelectableText(
                          _liveActionProtocolPreview,
                          maxLines: 3,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                    ] else
                      Text(
                        '注入详情已隐藏，内容仍会随请求发送。可在“AI 助手设置”中开启预览。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: colorScheme.onSurface.withValues(alpha: 0.68),
                        ),
                      ),
                    SelectableText(
                      '预计Token：~$_liveEstimatedTokens',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    Text(
                      '文本近似值，不含附件、财务/习惯明细或原生工具定义；实际用量以模型返回为准。',
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        color: colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_pendingAttachment != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildChatAttachmentPreview(
                        _pendingAttachment!,
                        compact: true,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _pendingAttachment = null;
                            _liveEstimatedTokens =
                                _estimateTokensForPendingInput(
                                  _inputCtrl.text.trim(),
                                );
                          });
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: '移除附件',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        style: floatingGlassPlainIconButtonStyle(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            AiChatComposer(
              controller: _inputCtrl,
              keyboardInset: MediaQuery.viewInsetsOf(context).bottom,
              modelSelector: _buildModelSelector(),
              contextLabel: _contextMode.label,
              isLoading: _isLoading,
              deepThinking: _deepThinking,
              contextEnabled: _smartContext,
              hasAttachment: _pendingAttachment != null,
              isPickingAttachment: _isPickingAttachment,
              onSend: _sendMessage,
              onVoice: _openVoiceInput,
              onStop: _stopGeneration,
              onAttach: _pickChatAttachment,
              onToggleThinking: () async {
                setState(() => _deepThinking = !_deepThinking);
                await ChatStorageService.setDeepThinkingEnabled(_deepThinking);
              },
              onToggleContext: () async {
                setState(() {
                  _smartContext = !_smartContext;
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
                await ChatStorageService.setSmartContextEnabled(_smartContext);
              },
              onSettings: _showPromptSettings,
              onModelConfig: _showModelConfig,
              onCopyPrompt: _inputHasText ? _copyManualPromptFromInput : null,
              onPasteReply: _pasteManualReplyFromClipboard,
              onRetry:
                  !_isLoading &&
                      _messages.isNotEmpty &&
                      _messages.last.role == ChatRole.assistant
                  ? _retryLastMessage
                  : null,
              onClearHistory: _clearHistory,
            ),
          ],
        ),
      ),
    );
    return SafeArea(
      // Keep the system inset outside the rounded shell so the shell hugs its
      // content instead of growing into the gesture/navigation area.
      top: false,
      left: false,
      right: false,
      child: FloatingGlassControl(
        height: null,
        margin: useFloating
            ? const EdgeInsets.fromLTRB(8, 4, 8, 8)
            : EdgeInsets.zero,
        borderRadius: useFloating ? 28 : 0,
        // Editable text must remain visible on Android devices that cannot
        // reliably composite a content-sized glass surface over the input
        // connection. Keep the floating capsule and use its native material
        // fallback for this interactive composer.
        useLiquidGlass: !AppPlatform.isAndroid,
        mobilePortraitOnly: true,
        child: content,
      ),
    );
  }
}
