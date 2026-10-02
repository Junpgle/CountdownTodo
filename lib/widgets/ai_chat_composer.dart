import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/page_transitions.dart';
import 'floating_glass_control.dart';

enum _ComposerAction { copy, paste, retry, model, settings, clear }

/// A full-width writing area with a separate toolbar. The owning screen keeps
/// the draft controller and all sending, attachment and configuration logic.
class AiChatComposer extends StatefulWidget {
  const AiChatComposer({
    super.key,
    required this.controller,
    required this.modelSelector,
    required this.contextLabel,
    required this.isLoading,
    required this.deepThinking,
    required this.contextEnabled,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.onToggleThinking,
    required this.onToggleContext,
    required this.onSettings,
    required this.onModelConfig,
    required this.onClearHistory,
    this.hasAttachment = false,
    this.isPickingAttachment = false,
    this.onCopyPrompt,
    this.onPasteReply,
    this.onRetry,
    this.keyboardInset,
  });

  final TextEditingController controller;
  final Widget modelSelector;
  final String contextLabel;
  final bool isLoading;
  final bool deepThinking;
  final bool contextEnabled;
  final bool hasAttachment;
  final bool isPickingAttachment;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAttach;
  final VoidCallback onToggleThinking;
  final VoidCallback onToggleContext;
  final VoidCallback onSettings;
  final VoidCallback onModelConfig;
  final VoidCallback onClearHistory;
  final VoidCallback? onCopyPrompt;
  final VoidCallback? onPasteReply;
  final VoidCallback? onRetry;

  /// Pass the inset from above Scaffold, which removes it from its body.
  final double? keyboardInset;

  @override
  State<AiChatComposer> createState() => _AiChatComposerState();
}

class _AiChatComposerState extends State<AiChatComposer> {
  final _focusNode = FocusNode();
  bool _expanded = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _expand() async {
    if (_expanded) return;
    setState(() => _expanded = true);
    await Navigator.of(context).push<void>(
      PageTransitions.material<void>(
        fullscreenDialog: true,
        builder: (_) => _ExpandedPromptEditor(controller: widget.controller),
      ),
    );
    if (!mounted) return;
    setState(() => _expanded = false);
    _focusNode.requestFocus();
  }

  void _sendFromKeyboard() {
    if (!widget.isLoading &&
        (widget.controller.text.trim().isNotEmpty || widget.hasAttachment)) {
      widget.onSend();
    }
  }

  void _selectAction(_ComposerAction action) {
    switch (action) {
      case _ComposerAction.copy:
        widget.onCopyPrompt?.call();
      case _ComposerAction.paste:
        widget.onPasteReply?.call();
      case _ComposerAction.retry:
        widget.onRetry?.call();
      case _ComposerAction.model:
        widget.onModelConfig();
      case _ComposerAction.settings:
        widget.onSettings();
      case _ComposerAction.clear:
        widget.onClearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final keyboardInset = widget.keyboardInset ?? media.viewInsets.bottom;
    final keyboardVisible = keyboardInset > 0;
    final availableHeight =
        media.size.height - keyboardInset - media.padding.vertical;
    final minLines = keyboardVisible && availableHeight < 240 ? 1 : 2;
    final lineHeight = media.textScaler.scale(15) * 1.4;
    final maxLines = keyboardVisible
        ? (availableHeight * 0.32 / lineHeight).floor().clamp(minLines, 6)
        : 6;
    final plainStyle = floatingGlassPlainIconButtonStyle().copyWith(
      minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
      maximumSize: const WidgetStatePropertyAll(Size(40, 40)),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    Widget option(
      IconData icon,
      bool selected,
      String tooltip,
      VoidCallback tap,
    ) => IconButton(
      onPressed: tap,
      tooltip: tooltip,
      isSelected: selected,
      icon: Icon(icon, size: 20),
      style: plainStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(
          selected ? colors.primary : colors.onSurfaceVariant,
        ),
        backgroundColor: WidgetStatePropertyAll(
          selected
              ? colors.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _sendFromKeyboard,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _sendFromKeyboard,
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!keyboardVisible)
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.modelSelector,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 136),
                  child: TextButton.icon(
                    onPressed: widget.onSettings,
                    icon: Icon(
                      widget.contextEnabled
                          ? Icons.manage_search_rounded
                          : Icons.search_off_rounded,
                      size: 15,
                    ),
                    label: Text(
                      widget.contextEnabled ? widget.contextLabel : '上下文已关闭',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: TextButton.styleFrom(
                      backgroundBuilder: plainStyle.backgroundBuilder,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      textStyle: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('ai-chat-input'),
                  controller: widget.controller,
                  focusNode: _focusNode,
                  readOnly: _expanded,
                  selectAllOnFocus: false,
                  minLines: minLines,
                  maxLines: maxLines,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: colors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '问问助手…',
                    hintStyle: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: colors.onSurfaceVariant,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed:
                            widget.isLoading || widget.isPickingAttachment
                            ? null
                            : widget.onAttach,
                        tooltip: '添加图片、音频、视频或文件',
                        style: plainStyle,
                        icon: widget.isPickingAttachment
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.attach_file_rounded, size: 20),
                      ),
                      option(
                        Icons.psychology_rounded,
                        widget.deepThinking,
                        '深度思考',
                        widget.onToggleThinking,
                      ),
                      option(
                        Icons.auto_awesome_rounded,
                        widget.contextEnabled,
                        '智能上下文 · ${widget.contextLabel}',
                        widget.onToggleContext,
                      ),
                      PopupMenuButton<_ComposerAction>(
                        key: const ValueKey('ai-chat-more'),
                        tooltip: '更多输入操作',
                        icon: const Icon(Icons.more_horiz_rounded, size: 20),
                        style: plainStyle,
                        onSelected: _selectAction,
                        onOpened: _focusNode.unfocus,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: _ComposerAction.copy,
                            enabled:
                                !widget.isLoading &&
                                widget.onCopyPrompt != null,
                            child: const Text('复制提示词'),
                          ),
                          PopupMenuItem(
                            value: _ComposerAction.paste,
                            enabled:
                                !widget.isLoading &&
                                widget.onPasteReply != null,
                            child: const Text('粘贴AI回复识别'),
                          ),
                          PopupMenuItem(
                            value: _ComposerAction.retry,
                            enabled:
                                !widget.isLoading && widget.onRetry != null,
                            child: const Text('重试上一条回复'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: _ComposerAction.model,
                            child: Text('模型配置'),
                          ),
                          const PopupMenuItem(
                            value: _ComposerAction.settings,
                            child: Text('AI 助手设置'),
                          ),
                          PopupMenuItem(
                            value: _ComposerAction.clear,
                            enabled: !widget.isLoading,
                            child: const Text('清空聊天记录'),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _expand,
                        tooltip: '展开编辑',
                        icon: const Icon(Icons.open_in_full_rounded, size: 18),
                        style: plainStyle,
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: widget.controller,
                        builder: (_, value, _) => IconButton(
                          key: const ValueKey('ai-chat-send'),
                          tooltip: widget.isLoading
                              ? '停止生成'
                              : '发送（Ctrl/⌘ + Enter）',
                          onPressed: widget.isLoading
                              ? widget.onStop
                              : value.text.trim().isNotEmpty ||
                                    widget.hasAttachment
                              ? widget.onSend
                              : null,
                          icon: Icon(
                            widget.isLoading
                                ? Icons.stop_rounded
                                : Icons.arrow_upward_rounded,
                            size: 20,
                          ),
                          style: plainStyle.copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.disabled)
                                  ? colors.surfaceContainerHighest
                                  : colors.primary,
                            ),
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.disabled)
                                  ? colors.onSurfaceVariant
                                  : colors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedPromptEditor extends StatelessWidget {
  const _ExpandedPromptEditor({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('编辑提示词'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: '收起编辑',
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('ai-chat-expanded-input'),
                controller: controller,
                autofocus: true,
                selectAllOnFocus: false,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: 15, height: 1.5),
                decoration: const InputDecoration(
                  hintText: '输入完整提示词…',
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
