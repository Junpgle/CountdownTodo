import 'dart:convert';

import '../models/thirty_day_challenge.dart';

/// 自定义挑战的可复制分享格式。
///
/// 使用带有 format 标记的 JSON，方便从聊天内容或导入文件中可靠识别，
/// 同时保留普通按行文本导入的兼容性。
abstract final class ChallengeShareCodec {
  static const String format = 'countdowntodo.challenge';
  static const int version = 1;

  static String encode(ChallengeDraft draft) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'title': draft.title.trim(),
      'tasks': draft.taskTitles
          .map((task) => task.trim())
          .where((task) => task.isNotEmpty)
          .toList(growable: false),
    });
  }

  static ChallengeDraft? tryDecode(String text) {
    final source = _removeCodeFence(text.trim());
    if (source.isEmpty) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      return null;
    }
    if (decoded is! Map || decoded['format']?.toString() != format) {
      return null;
    }

    final title = decoded['title']?.toString().trim() ?? '';
    final rawTasks = decoded['tasks'];
    final tasks = rawTasks is List
        ? rawTasks
            .map((task) => task.toString().trim())
            .where((task) => task.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    if (title.isEmpty || tasks.isEmpty) return null;

    return ChallengeDraft(title: title, taskTitles: tasks);
  }

  static String _removeCodeFence(String source) {
    if (!source.startsWith('```') || !source.endsWith('```')) {
      return source;
    }
    final lines = source.split('\n');
    if (lines.length < 3) return source;
    return lines.sublist(1, lines.length - 1).join('\n').trim();
  }
}
