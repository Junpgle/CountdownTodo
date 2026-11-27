import '../../../utils/emoji_utils.dart';

/// 习惯图标与 Emoji 解析辅助工具（委托至通用 [EmojiUtils]）。
abstract final class HabitEmojiUtils {
  /// 判断单个 Unicode 字素簇（grapheme cluster）是否为 Emoji。
  static bool isEmojiGrapheme(String grapheme) =>
      EmojiUtils.isEmojiGrapheme(grapheme);

  /// 从原始输入中提取单个图标（优先取最后一个完整 Emoji 字素簇；
  /// 若不包含 Emoji，则仅接受单个非空白符号/字符，拒绝多字符纯文本）。
  static String? extractSingleEmoji(String raw) =>
      EmojiUtils.extractSingleEmoji(raw);

  /// 规范化图标输入；无效时回退到 [fallback]。
  static String normalizeIcon(String raw, {String fallback = '🎯'}) =>
      EmojiUtils.normalizeIcon(raw, fallback: fallback);
}
