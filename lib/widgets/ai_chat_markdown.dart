import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// The same compact typography for streaming, saved and recognition replies.
class AiChatMarkdown extends StatelessWidget {
  const AiChatMarkdown({
    super.key,
    required this.data,
    this.isReasoning = false,
  });

  final String data;
  final bool isReasoning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = isReasoning ? 12.0 : 13.0;
    final text = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: isReasoning ? colors.onSurfaceVariant : colors.onSurface,
      fontSize: size,
      height: 1.35,
    );
    TextStyle heading(double extra) => text.copyWith(
      fontSize: size + extra,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    // This is an embedded message, so page safe-area padding must not shift
    // its scrollbar into table rows. The surrounding chat handles safe areas.
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: MarkdownBody(
        data: data,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: text,
          pPadding: EdgeInsets.zero,
          h1: heading(4),
          h2: heading(3),
          h3: heading(2),
          h4: heading(1),
          h5: heading(0),
          h6: heading(0),
          strong: const TextStyle(fontWeight: FontWeight.w600),
          em: const TextStyle(fontStyle: FontStyle.italic),
          del: const TextStyle(decoration: TextDecoration.lineThrough),
          a: TextStyle(color: colors.primary),
          listBullet: text.copyWith(color: colors.primary),
          listIndent: 18,
          listBulletPadding: const EdgeInsets.only(right: 3),
          blockSpacing: 6,
          code: text.copyWith(
            fontSize: size - 1,
            fontFamily: 'monospace',
            color: colors.secondary,
            backgroundColor: colors.secondaryContainer.withValues(alpha: 0.35),
          ),
          codeblockPadding: const EdgeInsets.all(8),
          codeblockDecoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          blockquote: text.copyWith(color: colors.onSurfaceVariant),
          blockquotePadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          blockquoteDecoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.12),
            border: Border(left: BorderSide(color: colors.primary, width: 2)),
          ),
          tableHead: text.copyWith(fontWeight: FontWeight.w600),
          tableBody: text,
          tableHeadAlign: TextAlign.left,
          // Markdown provides horizontal scrolling for fixed column widths.
          // Keep useful cell width on phones instead of squeezing every column
          // into the bubble and turning a short table into a very tall reply.
          tableColumnWidth: const FixedColumnWidth(152),
          tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
          // Reserve space for the thumb, including desktop hover/iOS dragging.
          tablePadding: const EdgeInsets.only(bottom: 16),
          tableScrollbarThumbVisibility: true,
          tableBorder: TableBorder.all(
            color: colors.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
    );
  }
}
