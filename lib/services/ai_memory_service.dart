import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiMemoryItem {
  final String id;
  final String content;
  final int createdAtMs;
  final int updatedAtMs;
  final String source;

  const AiMemoryItem({
    required this.id,
    required this.content,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.source = 'manual',
  });

  AiMemoryItem copyWith({
    String? id,
    String? content,
    int? createdAtMs,
    int? updatedAtMs,
    String? source,
  }) {
    return AiMemoryItem(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
    'source': source,
  };

  factory AiMemoryItem.fromJson(Map<String, dynamic> json) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return AiMemoryItem(
      id: json['id']?.toString() ?? 'mem_$nowMs',
      content: json['content']?.toString().trim() ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? nowMs,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? nowMs,
      source: json['source']?.toString() == 'ai' ? 'ai' : 'manual',
    );
  }
}

class AiMemoryService {
  AiMemoryService._();

  static const String toolName = 'manage_user_memory';
  static const int maxItems = 20;
  static const int maxItemLength = 120;

  static const String _enabledKey = 'ai_memory_enabled';
  static const String _itemsKey = 'ai_memory_items';
  static final RegExp _memoryBlockPattern = RegExp(
    r'\[MEMORY_START\]([\s\S]*?)\[MEMORY_END\]',
  );

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _scoped(String baseKey, String? username) {
    final normalized = (username ?? '').trim();
    if (normalized.isEmpty) return baseKey;
    return '${baseKey}_$normalized';
  }

  static String normalizeContent(String raw) {
    final compact = raw.replaceAll(_rxCached23_1, ' ').trim();
    if (compact.length <= maxItemLength) return compact;
    return compact.substring(0, maxItemLength).trim();
  }

  static Future<bool> isEnabled(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_scoped(_enabledKey, username)) ?? true;
  }

  static Future<void> setEnabled(String? username, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scoped(_enabledKey, username), enabled);
    revision.value++;
  }

  static Future<List<AiMemoryItem>> loadMemories(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scoped(_itemsKey, username));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => AiMemoryItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.content.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveMemories(
    String? username,
    List<AiMemoryItem> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = items
        .where((item) => item.content.trim().isNotEmpty)
        .take(maxItems)
        .map((item) => item.toJson())
        .toList();
    await prefs.setString(_scoped(_itemsKey, username), jsonEncode(trimmed));
    revision.value++;
  }

  static Future<AiMemoryItem?> addMemory(
    String? username,
    String rawContent, {
    String source = 'manual',
    DateTime? now,
  }) async {
    final content = normalizeContent(rawContent);
    if (content.isEmpty) return null;
    final current = List<AiMemoryItem>.from(await loadMemories(username));
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final normalizedLower = content.toLowerCase();
    final existingIndex = current.indexWhere(
      (item) => item.content.toLowerCase() == normalizedLower,
    );
    late final AiMemoryItem savedItem;
    if (existingIndex >= 0) {
      savedItem = current[existingIndex].copyWith(
        content: content,
        updatedAtMs: nowMs,
        source: source,
      );
      current.removeAt(existingIndex);
      current.insert(0, savedItem);
    } else {
      savedItem = AiMemoryItem(
        id: 'mem_${nowMs}_${current.length}',
        content: content,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
        source: source == 'ai' ? 'ai' : 'manual',
      );
      current.insert(0, savedItem);
      if (current.length > maxItems) {
        current.removeRange(maxItems, current.length);
      }
    }
    await saveMemories(username, current);
    return savedItem;
  }

  static Future<bool> updateMemory(
    String? username,
    String id,
    String rawContent, {
    DateTime? now,
  }) async {
    final content = normalizeContent(rawContent);
    if (content.isEmpty) return false;
    final current = List<AiMemoryItem>.from(await loadMemories(username));
    final index = current.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    current[index] = current[index].copyWith(
      content: content,
      updatedAtMs: nowMs,
    );
    await saveMemories(username, current);
    return true;
  }

  static Future<bool> deleteMemory(String? username, String id) async {
    final current = List<AiMemoryItem>.from(await loadMemories(username));
    final before = current.length;
    current.removeWhere((item) => item.id == id);
    if (current.length == before) return false;
    await saveMemories(username, current);
    return true;
  }

  static Future<int> deleteMemoryByContent(
    String? username,
    String rawQuery,
  ) async {
    final query = normalizeContent(rawQuery).toLowerCase();
    if (query.isEmpty) return 0;
    final current = List<AiMemoryItem>.from(await loadMemories(username));
    final before = current.length;
    current.removeWhere((item) {
      final lower = item.content.toLowerCase();
      return lower == query || lower.contains(query) || query.contains(lower);
    });
    final removed = before - current.length;
    if (removed > 0) {
      await saveMemories(username, current);
    }
    return removed;
  }

  static Future<void> clearMemories(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scoped(_itemsKey, username));
    revision.value++;
  }

  static String buildPromptBlock(List<AiMemoryItem> memories) {
    final valid = memories.where((m) => m.content.trim().isNotEmpty).toList();
    if (valid.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('【用户长期偏好记忆】')
      ..writeln('以下偏好由用户设置或明确要求记住，回答与规划时请优先遵守；若与本轮明确指令冲突，以本轮为准：');
    for (final item in valid.take(maxItems)) {
      buffer.writeln('- ${item.content}');
    }
    return buffer.toString().trim();
  }

  static Future<String> loadPromptBlock(String? username) async {
    if (!await isEnabled(username)) return '';
    final items = await loadMemories(username);
    return buildPromptBlock(items);
  }

  static Map<String, dynamic> buildDefinition() {
    return {
      'type': 'function',
      'function': {
        'name': toolName,
        'description': '保存或删除用户的长期偏好记忆（如作息习惯、学习/工作时段偏好、称呼、回复风格等）。仅当用户明确要求记住/忘掉某项偏好，或表达了明确的长期固定习惯时调用；不要把一次性待办或单次日期安排存为记忆。',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['save', 'delete'],
              'description': 'save=保存一条新偏好或更新已有偏好；delete=按关键词删除匹配的偏好记忆',
            },
            'content': {
              'type': 'string',
              'description': '简洁的一句话偏好描述（不超过120字），例如：晚上22:00后不安排高强度学习',
            },
          },
          'required': ['action', 'content'],
          'additionalProperties': false,
        },
      },
    };
  }

  static String buildInstructionPrompt({required bool nativeToolCalls}) {
    if (nativeToolCalls) {
      return '【用户偏好记忆规则】\n'
          '当用户明确要求记住/忘掉某项长期偏好、作息习惯、回复风格或称呼，或表达明确的长期规律时，可调用 $toolName 保存或删除，并在回复中简短告知用户；不要把一次性待办或临时安排写入记忆。';
    }
    return '【用户偏好记忆规则】\n'
        '当用户明确要求记住/忘掉某项长期偏好、作息习惯或回复风格时，可在正文末尾附加：\n'
        '[MEMORY_START]{"action":"save","content":"简洁的长期偏好描述"}[MEMORY_END]\n'
        '（删除时将 action 改为 "delete"）。不要把一次性待办写入记忆。';
  }

  static Future<Map<String, dynamic>> executeToolCall(
    String? username,
    Map<String, dynamic> arguments,
  ) async {
    if (!await isEnabled(username)) {
      return {
        'ok': false,
        'status': 'memory_disabled',
        'message': '用户已在设置中关闭 AI 记忆功能，本次未保存偏好。',
      };
    }
    final action = arguments['action']?.toString().trim().toLowerCase() ?? '';
    final content = normalizeContent(arguments['content']?.toString() ?? '');
    if (content.isEmpty) {
      return {
        'ok': false,
        'status': 'invalid_content',
        'message': '偏好内容为空，未修改记忆。',
      };
    }
    if (action == 'save') {
      final saved = await addMemory(username, content, source: 'ai');
      if (saved == null) {
        return {'ok': false, 'status': 'save_failed', 'message': '保存偏好失败。'};
      }
      return {
        'ok': true,
        'status': 'saved',
        'action': 'save',
        'content': saved.content,
        'message': '已记住用户偏好：${saved.content}',
      };
    }
    if (action == 'delete') {
      final removed = await deleteMemoryByContent(username, content);
      return {
        'ok': removed > 0,
        'status': removed > 0 ? 'deleted' : 'not_found',
        'action': 'delete',
        'removedCount': removed,
        'message': removed > 0
            ? '已从记忆中移除相关偏好（共 $removed 条）。'
            : '未在记忆中找到与「$content」匹配的偏好。',
      };
    }
    return {
      'ok': false,
      'status': 'unsupported_action',
      'message': '不支持的记忆操作：$action',
    };
  }

  static List<Map<String, dynamic>> extractTextMemoryCommands(String content) {
    final commands = <Map<String, dynamic>>[];
    for (final match in _memoryBlockPattern.allMatches(content)) {
      final rawJson = match.group(1)?.trim() ?? '';
      if (rawJson.isEmpty) continue;
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic>) {
          commands.add(decoded);
        } else if (decoded is Map) {
          commands.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return commands;
  }

  static Future<List<String>> applyTextMemoryCommands(
    String? username,
    String content,
  ) async {
    final commands = extractTextMemoryCommands(content);
    if (commands.isEmpty) return const [];
    final notices = <String>[];
    for (final command in commands) {
      final result = await executeToolCall(username, command);
      if (result['ok'] == true) {
        final msg = result['message']?.toString().trim() ?? '';
        if (msg.isNotEmpty) notices.add(msg);
      }
    }
    return notices;
  }

  static String cleanContent(String content) {
    return content.replaceAll(_memoryBlockPattern, '').trim();
  }
}

// Cached RegExp patterns
final RegExp _rxCached23_1 = RegExp(r'\s+');
