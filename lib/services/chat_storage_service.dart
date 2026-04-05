import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';

class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;

  ChatSession({
    String? id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int,
        isUtc: true,
      ).toLocal(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] as int,
        isUtc: true,
      ).toLocal(),
    );
  }
}

class ChatStorageService {
  static const String _sessionsKey = 'chat_sessions';
  static const String _activeSessionKey = 'chat_active_session';
  static const String _customPromptKey = 'chat_custom_prompt';
  static const String _promptEnabledKey = 'chat_prompt_enabled';
  static const String _chatModelKey = 'chat_model';
  static const String _chatApiKeyKey = 'chat_api_key';
  static const String _chatApiUrlKey = 'chat_api_url';
  static const String _defaultPrompt = '''你是一个智能待办助手，帮助用户管理他们的待办事项。

【当前时间】
{now}

【用户当前待办清单】
{todos}

【你的能力】
1. 帮助用户分析和排序待办事项的优先级
2. 建议合理的执行顺序（考虑时间紧迫性、重要程度、依赖关系等）
3. 回答用户关于待办的任何问题
4. 提供时间管理建议
5. 支持Markdown格式回复，可以使用列表、加粗等格式

【回复要求】
- 使用Markdown格式回复
- 回答要简洁明了
- 给出具体可执行的建议
- 如果要排序，使用有序列表格式
- 如果涉及时间，请说明理由''';

  static String get defaultPrompt => _defaultPrompt;

  static String _historyKey(String sessionId) => 'chat_history_$sessionId';

  static Future<List<ChatSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsStr = prefs.getString(_sessionsKey);
    if (sessionsStr == null || sessionsStr.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> jsonList = jsonDecode(sessionsStr);
      return jsonList
          .map((json) => ChatSession.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveSessions(List<ChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_sessionsKey, jsonEncode(jsonList));
  }

  static Future<String?> getActiveSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeSessionKey);
  }

  static Future<void> setActiveSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeSessionKey, sessionId);
  }

  static Future<ChatSession> createSession({String? title}) async {
    final sessions = await loadSessions();
    final newSession = ChatSession(
      title: title ?? '新对话',
    );
    sessions.insert(0, newSession);
    await saveSessions(sessions);
    await setActiveSessionId(newSession.id);
    return newSession;
  }

  static Future<void> deleteSession(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadSessions();
    sessions.removeWhere((s) => s.id == sessionId);
    await saveSessions(sessions);
    await prefs.remove(_historyKey(sessionId));
    final activeId = await getActiveSessionId();
    if (activeId == sessionId && sessions.isNotEmpty) {
      await setActiveSessionId(sessions.first.id);
    } else if (sessions.isEmpty) {
      await prefs.remove(_activeSessionKey);
    }
  }

  static Future<void> updateSessionTitle(
    String sessionId,
    String title,
  ) async {
    final sessions = await loadSessions();
    final session = sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => throw Exception('Session not found'),
    );
    session.title = title;
    session.updatedAt = DateTime.now();
    await saveSessions(sessions);
  }

  static Future<List<ChatMessage>> loadHistory([String? sessionId]) async {
    final prefs = await SharedPreferences.getInstance();
    final sid = sessionId ?? await getActiveSessionId();
    if (sid == null) return [];
    final historyStr = prefs.getString(_historyKey(sid));
    if (historyStr == null || historyStr.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> jsonList = jsonDecode(historyStr);
      return jsonList
          .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveHistory(
    List<ChatMessage> history, [
    String? sessionId,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    final sid = sessionId ?? await getActiveSessionId();
    if (sid == null) return;
    final jsonList = history.map((msg) => msg.toJson()).toList();
    await prefs.setString(_historyKey(sid), jsonEncode(jsonList));
  }

  static Future<void> addMessage(ChatMessage message) async {
    final history = await loadHistory();
    history.add(message);
    await saveHistory(history);
    if (history.length == 2 && message.role == ChatRole.assistant) {
      final sessions = await loadSessions();
      final activeId = await getActiveSessionId();
      if (activeId != null) {
        final session = sessions.firstWhere(
          (s) => s.id == activeId,
          orElse: () => throw Exception('Session not found'),
        );
        if (session.title == '新对话') {
          final firstUserMsg = history.firstWhere(
            (m) => m.role == ChatRole.user,
            orElse: () => message,
          );
          session.title = firstUserMsg.content.length > 20
              ? '${firstUserMsg.content.substring(0, 20)}...'
              : firstUserMsg.content;
          session.updatedAt = DateTime.now();
          await saveSessions(sessions);
        }
      }
    }
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final sid = await getActiveSessionId();
    if (sid != null) {
      await prefs.remove(_historyKey(sid));
    }
  }

  static Future<String> getCustomPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customPromptKey) ?? _defaultPrompt;
  }

  static Future<void> saveCustomPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    if (prompt.trim().isEmpty) {
      await prefs.remove(_customPromptKey);
    } else {
      await prefs.setString(_customPromptKey, prompt);
    }
  }

  static Future<bool> isPromptEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_promptEnabledKey) ?? true;
  }

  static Future<void> setPromptEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptEnabledKey, enabled);
  }

  static Future<void> resetPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customPromptKey);
  }

  static Future<Map<String, String>?> getChatConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString(_chatModelKey);
    final apiKey = prefs.getString(_chatApiKeyKey);
    final apiUrl = prefs.getString(_chatApiUrlKey);
    if (model == null || model.isEmpty) return null;
    return {
      'model': model,
      'apiKey': apiKey ?? '',
      'apiUrl':
          apiUrl ?? 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    };
  }

  static Future<void> saveChatConfig({
    required String model,
    required String apiKey,
    String? apiUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (model.isEmpty) {
      await prefs.remove(_chatModelKey);
      await prefs.remove(_chatApiKeyKey);
      await prefs.remove(_chatApiUrlKey);
    } else {
      await prefs.setString(_chatModelKey, model);
      if (apiKey.isNotEmpty) {
        await prefs.setString(_chatApiKeyKey, apiKey);
      }
      if (apiUrl != null && apiUrl.isNotEmpty) {
        await prefs.setString(_chatApiUrlKey, apiUrl);
      }
    }
  }

  static Future<void> clearChatConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatModelKey);
    await prefs.remove(_chatApiKeyKey);
    await prefs.remove(_chatApiUrlKey);
  }
}
