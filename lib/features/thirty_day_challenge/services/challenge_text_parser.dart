/// 将用户输入的文本清洗为挑战任务。
///
/// 每一行代表一项任务；空行会被忽略，常见的 Markdown/数字列表前缀会被
/// 去掉，方便直接粘贴笔记或清单内容。
abstract final class ChallengeTextParser {
  static List<String> parseTaskTitles(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map(_normalizeLine)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  static String _normalizeLine(String line) {
    var normalized = line.replaceFirst('\uFEFF', '').trim();
    normalized = normalized.replaceFirst(
      RegExp(r'^(?:[-*•·]|\d+[.)、])\s+'),
      '',
    );
    return normalized.trim();
  }
}
