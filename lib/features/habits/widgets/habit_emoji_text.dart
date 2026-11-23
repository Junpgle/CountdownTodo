import 'package:flutter/material.dart';

/// 将包含彩色 Emoji 与中日韩文字的混排文案拆分为独立的文字段与 Emoji 段，
/// 避免 macOS Impeller / Skia 在同一字形 run 中混排 Emoji 与汉字时出现方块乱码。
class HabitEmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const HabitEmojiText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  static bool _isEmojiGrapheme(String grapheme) {
    final runes = grapheme.runes;
    if (runes.isEmpty) return false;
    for (final rune in runes) {
      if (rune >= 0x1F000 ||
          (rune >= 0x2600 && rune <= 0x27BF) ||
          rune == 0xFE0F ||
          rune == 0x200D) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var hasEmoji = false;

    for (final grapheme in text.characters) {
      if (_isEmojiGrapheme(grapheme)) {
        hasEmoji = true;
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(text: buffer.toString()));
          buffer.clear();
        }
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Text(grapheme, style: style),
          ),
        );
      } else {
        buffer.write(grapheme);
      }
    }

    if (!hasEmoji) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    if (buffer.isNotEmpty) {
      spans.add(TextSpan(text: buffer.toString()));
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
