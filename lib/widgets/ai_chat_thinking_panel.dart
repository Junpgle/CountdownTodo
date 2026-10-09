import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import 'ai_chat_markdown.dart';
import 'ai_tool_call_tile.dart';

/// Reasoning and function calls share one disclosure before the reply.
class AiChatThinkingPanel extends StatefulWidget {
  const AiChatThinkingPanel({
    super.key,
    this.reasoning = '',
    this.calls = const [],
    this.isStreaming = false,
    this.hasReply = false,
    this.finishReason,
  });

  final String reasoning;
  final List<ChatNativeToolCall> calls;
  final bool isStreaming;
  final bool hasReply;
  final String? finishReason;

  @override
  State<AiChatThinkingPanel> createState() => _AiChatThinkingPanelState();
}

class _AiChatThinkingPanelState extends State<AiChatThinkingPanel> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant AiChatThinkingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Collapse once when the answer arrives or generation ends. A later manual
    // expansion must survive further answer tokens and tool-result updates.
    if ((!oldWidget.hasReply && widget.hasReply) ||
        (!widget.hasReply && oldWidget.isStreaming && !widget.isStreaming)) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reasoning.trim().isEmpty && widget.calls.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final thinking = widget.isStreaming && !widget.hasReply;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.psychology_outlined,
                        size: 15,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '思考过程',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface,
                        ),
                      ),
                      if (widget.calls.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${widget.calls.length} 次工具调用',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (thinking) ...[
                        SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.4,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded) ...[
              if (widget.reasoning.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
                  child: AiChatMarkdown(
                    data: widget.reasoning,
                    isReasoning: true,
                  ),
                ),
              for (final (index, call) in widget.calls.indexed)
                AiToolCallTile(
                  key: ValueKey(
                    call.id.isNotEmpty ? call.id : 'pending-$index',
                  ),
                  call: call,
                ),
              if (widget.finishReason != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 3, 10, 7),
                  child: Text(
                    '结束原因：${widget.finishReason}',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
