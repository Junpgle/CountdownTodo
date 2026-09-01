part of 'todo_chat_screen.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatMessages on _TodoChatScreenStateBase {
  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    final isUser = msg.role == ChatRole.user;
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);
    final colorScheme = Theme.of(context).colorScheme;
    final maxBubbleWidth = MediaQuery.of(context).size.width >= 900
        ? 680.0
        : MediaQuery.of(context).size.width * 0.78;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(
                  Icons.smart_toy_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isUser && msg.reasoningContent.isNotEmpty)
                    _buildCollapsibleReasoning(
                      msg.reasoningContent,
                      isDark,
                      false,
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? colorScheme.primary
                          : isDark
                              ? colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.55)
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
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.55),
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
                                    fontSize: 15,
                                    height: 1.42,
                                  ),
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
                                MarkdownBody(
                                  data: msg.content,
                                  styleSheet: MarkdownStyleSheet(
                                    p: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 15,
                                      height: 1.45,
                                    ),
                                    strong: TextStyle(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    listBullet: TextStyle(
                                      color: colorScheme.primary,
                                      fontSize: 15,
                                    ),
                                    code: TextStyle(
                                      color: colorScheme.secondary,
                                      backgroundColor: colorScheme
                                          .secondaryContainer
                                          .withValues(alpha: 0.5),
                                      fontSize: 14,
                                      fontFamily: 'monospace',
                                    ),
                                    blockquote: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    blockquoteDecoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: colorScheme.primary,
                                          width: 4,
                                        ),
                                      ),
                                      color: colorScheme.primaryContainer
                                          .withValues(alpha: 0.1),
                                    ),
                                  ),
                                  selectable: true,
                                ),
                              if (msg.usageSummary != null)
                                _buildUsageSummaryFooter(msg.usageSummary!),
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
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
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
                                    color: colorScheme.primary
                                        .withValues(alpha: 0.82),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '原始回复',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.primary
                                          .withValues(alpha: 0.88),
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
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: colorScheme.secondary.withValues(alpha: 0.1),
                child: Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: colorScheme.secondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollapsibleReasoning(
    String reasoning,
    bool isDark,
    bool isStreaming,
  ) {
    return _CollapsibleReasoningWidget(
      reasoning: reasoning,
      isDark: isDark,
      isStreaming: isStreaming,
    );
  }

  Widget _buildStreamingBubble(bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _PulseAvatar(
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.smart_toy_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_streamingReasoning.isNotEmpty)
                  _buildCollapsibleReasoning(_streamingReasoning, isDark, true),
                if (_streamingContent.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.4)
                          : Colors.white,
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
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: MarkdownBody(
                      data: _streamingContent,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 15,
                          height: 1.4,
                        ),
                        strong: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        code: TextStyle(
                          color: colorScheme.secondary,
                          backgroundColor: colorScheme.secondaryContainer
                              .withValues(alpha: 0.5),
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                      selectable: true,
                    ),
                  )
                else if (_streamingReasoning.isEmpty)
                  const _ThinkingLoader(),
              ],
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
                    [attachment.typeLabel, sizeLabel]
                        .where((item) => item.isNotEmpty)
                        .join(' · '),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: preview,
      ),
    );
  }

  Widget _buildUsageSummaryFooter(ChatUsageSummary usage) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[];
    if (usage.costMicros != null) {
      parts.add('本次花费 ${AiUsageCostService.formatMicros(usage.costMicros!)}');
    } else {
      parts.add('本次费用暂无可用价格');
    }
    if (usage.totalTokens > 0) parts.add('${usage.totalTokens} tokens');
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
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.toll_rounded,
            size: 12,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
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
          MarkdownBody(
            data: msg.content,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                height: 1.45,
              ),
              strong: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            selectable: true,
          ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildModelSelector(),
                  ),
                ),
                if (!_isLoading && _inputHasText)
                  TextButton.icon(
                    icon: const Icon(Icons.content_copy_rounded, size: 16),
                    label: const Text('复制提示词'),
                    onPressed: _copyManualPromptFromInput,
                    style: TextButton.styleFrom(
                      backgroundBuilder: _keepTodoChatButtonBackground,
                      backgroundColor: Colors.transparent,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (!_isLoading)
                  IconButton(
                    icon: Icon(
                      Icons.assignment_rounded,
                      size: 17,
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                    ),
                    onPressed: _pasteManualReplyFromClipboard,
                    tooltip: '粘贴AI回复识别',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    style: floatingGlassPlainIconButtonStyle(),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.delete_sweep_rounded,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  onPressed: _clearHistory,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                  style: floatingGlassPlainIconButtonStyle(),
                ),
              ],
            ),
            if (_inputHasText &&
                (_liveSmartContextPreview.isNotEmpty ||
                    _liveActionProtocolPreview.isNotEmpty)) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                              if (_injectMoreContext) {
                                _useCustomInjectRange = false;
                              }
                              _liveSmartContextPreview =
                                  _buildSmartContextPreview(
                                      _inputCtrl.text.trim());
                              _liveActionProtocolPreview =
                                  _buildActionProtocolPreview(
                                      _inputCtrl.text.trim());
                              _liveEstimatedTokens =
                                  _estimateTokensForPendingInput(
                                      _inputCtrl.text.trim());
                            });
                          },
                          style: TextButton.styleFrom(
                            backgroundBuilder: _keepTodoChatButtonBackground,
                            backgroundColor: Colors.transparent,
                            minimumSize: const Size(0, 22),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
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
                                horizontal: 8, vertical: 2),
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
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      if (_liveSmartContextPreview.isEmpty)
                        Text(
                          '将注入：无（当前消息无需额外业务上下文）',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.65),
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
                        onPressed: () =>
                            setState(() => _pendingAttachment = null),
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
            Container(
              decoration: BoxDecoration(
                // The enclosing FloatingGlassControl already owns the
                // material. Keep the composer row transparent in its
                // floating form so it does not become a second glass capsule.
                color: useFloating
                    ? Colors.transparent
                    : isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(
                    alpha: useFloating ? 0.18 : 0.3,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _isLoading ? null : _pickChatAttachment,
                    icon: _isPickingAttachment
                        ? SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.attach_file_rounded,
                            size: 18,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.65),
                          ),
                    tooltip: '添加图片、音频、视频或文件',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    style: floatingGlassPlainIconButtonStyle(),
                  ),
                  _buildIconButtonOption(
                    icon: Icons.psychology_rounded,
                    isSelected: _deepThinking,
                    tooltip: '深度思考',
                    onTap: (val) async {
                      setState(() => _deepThinking = val);
                      await ChatStorageService.setDeepThinkingEnabled(val);
                    },
                  ),
                  _buildIconButtonOption(
                    icon: Icons.auto_awesome_rounded,
                    isSelected: _smartContext,
                    tooltip: '智能上下文',
                    onTap: (val) async {
                      setState(() {
                        _smartContext = val;
                        _liveSmartContextPreview =
                            _buildSmartContextPreview(_inputCtrl.text.trim());
                        _liveActionProtocolPreview =
                            _buildActionProtocolPreview(_inputCtrl.text.trim());
                        _liveEstimatedTokens = _estimateTokensForPendingInput(
                            _inputCtrl.text.trim());
                      });
                      await ChatStorageService.setSmartContextEnabled(val);
                    },
                  ),
                  const SizedBox(width: 4),
                  Container(
                    height: 20,
                    width: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '问问助手...',
                        hintStyle: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                          fontSize: 14,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (!_isLoading &&
                      _messages.isNotEmpty &&
                      _messages.last.role == ChatRole.assistant)
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: '重试',
                      onPressed: _retryLastMessage,
                      style: floatingGlassPlainIconButtonStyle().copyWith(
                        foregroundColor: WidgetStatePropertyAll(
                          colorScheme.onSurfaceVariant,
                        ),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      ),
                      child: _isLoading
                          ? const Icon(
                              Icons.stop_rounded,
                              key: ValueKey('stop'),
                              size: 20,
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              key: ValueKey('send'),
                              size: 20,
                            ),
                    ),
                    onPressed: _isLoading ? _stopGeneration : _sendMessage,
                    style: floatingGlassPlainIconButtonStyle().copyWith(
                      backgroundColor:
                          WidgetStatePropertyAll(colorScheme.primary),
                      foregroundColor:
                          WidgetStatePropertyAll(colorScheme.onPrimary),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.all(8),
                      ),
                    ),
                  ),
                ],
              ),
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

  Widget _buildIconButtonOption({
    required IconData icon,
    required bool isSelected,
    required String tooltip,
    required Function(bool) onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onTap(!isSelected),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            scale: isSelected ? 1.08 : 1,
            child: Icon(
              icon,
              size: 18,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
