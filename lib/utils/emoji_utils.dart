import 'package:flutter/widgets.dart';

/// 通用图标与 Emoji 解析辅助工具。
abstract final class EmojiUtils {
  static const Set<int> _bmpEmojiSingles = <int>{
    0x00A9,
    0x00AE,
    0x203C,
    0x2049,
    0x2122,
    0x2139,
    0x24C2,
    0x25B6,
    0x25C0,
    0x2934,
    0x2935,
    0x3030,
    0x303D,
    0x3297,
    0x3299,
  };

  /// 判断单个 Unicode 字素簇（grapheme cluster）是否为 Emoji。
  static bool isEmojiGrapheme(String grapheme) {
    final runes = grapheme.runes;
    if (runes.isEmpty) return false;
    for (final rune in runes) {
      if (rune >= 0x1F000 ||
          (rune >= 0x2600 && rune <= 0x27BF) ||
          (rune >= 0x2300 && rune <= 0x23FF) ||
          (rune >= 0x2B00 && rune <= 0x2BFF) ||
          rune == 0x20E3 ||
          rune == 0xFE0F ||
          rune == 0x200D ||
          (rune >= 0x2194 && rune <= 0x2199) ||
          (rune >= 0x21A9 && rune <= 0x21AA) ||
          (rune >= 0x25AA && rune <= 0x25AB) ||
          (rune >= 0x25FB && rune <= 0x25FE) ||
          _bmpEmojiSingles.contains(rune)) {
        return true;
      }
    }
    return false;
  }

  /// 从原始输入中提取单个图标（优先取最后一个完整 Emoji 字素簇；
  /// 若不包含 Emoji，则仅接受单个非空白符号/字符，拒绝多字符纯文本）。
  static String? extractSingleEmoji(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    String? lastEmoji;
    for (final grapheme in trimmed.characters) {
      if (isEmojiGrapheme(grapheme)) {
        lastEmoji = grapheme;
      }
    }
    if (lastEmoji != null) {
      return lastEmoji;
    }

    final chars = trimmed.characters;
    if (chars.length == 1) {
      final single = chars.first;
      if (single.trim().isNotEmpty) {
        return single;
      }
    }
    return null;
  }

  /// 规范化图标输入；无效时回退到 [fallback]。
  static String normalizeIcon(String raw, {String fallback = '🎯'}) {
    return extractSingleEmoji(raw) ?? fallback;
  }
}
