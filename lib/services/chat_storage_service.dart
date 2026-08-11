import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import 'storage/user_session_storage.dart';
import 'storage/storage_key_scope.dart';

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
  static const String _chatProviderKey = 'chat_provider';
  static const String _deepThinkingKey = 'chat_deep_thinking';

  // 🚀 私有助手：获取隔离的存储 Key
  static Future<String> _getScopedKey(String baseKey) async {
    final username = await UserSessionStorage.getCurrentUsername();
    return StorageKeyScope.scoped(baseKey, username);
  }

  static const String _defaultPrompt =
      '''你是一个智能效率助手，帮助用户分别管理待办、固定日程、规划块、专注记录、番茄钟、倒计时和番茄标签。

【当前时间】
{now}

【用户当前待办清单】
{todos}

【你的能力】
1. 创建、修改、完成、删除、延期、分类、拆分、合并待办
2. 创建、修改、取消、删除固定日程，并区分时间待定、结束待定和明确时间段
3. 分析优先级，建议执行顺序（考虑时间紧迫性、重要程度、依赖关系）
4. 制定每日/每周计划，把已有待办安排为可调整的规划块
5. 新增、修改、删除专注记录
6. 开始或停止番茄钟
7. 新增、修改、完成、删除倒计时
8. 新增、改名、改色、删除番茄标签
9. 当用户提及课程、日程、专注记录、团队协作等话题时，系统会自动提供相关上下文

【回复要求】
- 使用Markdown格式，简洁明了
- 给出具体可执行的建议
- 涉及时间安排时说明理由
- 待办表示要完成的结果，规划块表示用户可调整的执行时段，考试/课程/会议等外部时间约束属于固定日程
- 不得为了容纳时间段把固定日程创建成待办，也不得把可调整的自我执行时段创建成固定日程
- 没有日期时不要默认今天全天；重复待办也不要自动称为习惯
- 循环待办和循环日程都由多个可独立寻址的真实期次组成；修改默认只针对本期，只有用户明确要求时才修改本期及以后；完成只属于待办单期，取消日程使用独立状态''';

  static String get defaultPrompt => _defaultPrompt;

  static String _historyKey(String sessionId) => 'chat_history_$sessionId';

  static Future<List<ChatSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_sessionsKey);
    String? sessionsStr = prefs.getString(scopedKey);

    // 迁移检查：如果用户隔离 Key 为空，尝试从全局 Key 迁移（仅一次）
    if (sessionsStr == null || sessionsStr.isEmpty) {
      final String? username = await UserSessionStorage.getCurrentUsername();
      if (username != null && username.isNotEmpty) {
        final markerKey = "${_sessionsKey}_${username}_migrated";
        if (!(prefs.getBool(markerKey) ?? false)) {
          sessionsStr = prefs.getString(_sessionsKey);
          if (sessionsStr != null) {
            await prefs.setString(scopedKey, sessionsStr);
            await prefs.setBool(markerKey, true);
          }
        }
      }
    }

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
    final scopedKey = await _getScopedKey(_sessionsKey);
    final jsonList = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(scopedKey, jsonEncode(jsonList));
  }

  static Future<void> clearAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadSessions();
    for (final s in sessions) {
      final hKey = await _getScopedKey(_historyKey(s.id));
      await prefs.remove(hKey);
    }
    final sKey = await _getScopedKey(_sessionsKey);
    final aKey = await _getScopedKey(_activeSessionKey);
    await prefs.remove(sKey);
    await prefs.remove(aKey);
  }

  static Future<String?> getActiveSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_activeSessionKey);
    return prefs.getString(scopedKey);
  }

  static Future<void> setActiveSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_activeSessionKey);
    await prefs.setString(scopedKey, sessionId);
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
    final hKey = await _getScopedKey(_historyKey(sessionId));
    await prefs.remove(hKey);
    final activeId = await getActiveSessionId();
    if (activeId == sessionId && sessions.isNotEmpty) {
      await setActiveSessionId(sessions.first.id);
    } else if (sessions.isEmpty) {
      final aKey = await _getScopedKey(_activeSessionKey);
      await prefs.remove(aKey);
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
    final hKey = await _getScopedKey(_historyKey(sid));
    final historyStr = prefs.getString(hKey);
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
    final hKey = await _getScopedKey(_historyKey(sid));
    await prefs.setString(hKey, jsonEncode(jsonList));
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
      final hKey = await _getScopedKey(_historyKey(sid));
      await prefs.remove(hKey);
    }
  }

  static Future<String> getCustomPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_customPromptKey);
    return prefs.getString(scopedKey) ?? _defaultPrompt;
  }

  static Future<void> saveCustomPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_customPromptKey);
    if (prompt.trim().isEmpty) {
      await prefs.remove(scopedKey);
    } else {
      await prefs.setString(scopedKey, prompt);
    }
  }

  static Future<bool> isPromptEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_promptEnabledKey);
    return prefs.getBool(scopedKey) ?? true;
  }

  static Future<void> setPromptEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_promptEnabledKey);
    await prefs.setBool(scopedKey, enabled);
  }

  static Future<void> resetPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_customPromptKey);
    await prefs.remove(scopedKey);
  }

  static Future<Map<String, String>?> getChatConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final mKey = await _getScopedKey(_chatModelKey);
    final kKey = await _getScopedKey(_chatApiKeyKey);
    final uKey = await _getScopedKey(_chatApiUrlKey);
    final pKey = await _getScopedKey(_chatProviderKey);

    String? model = prefs.getString(mKey);
    String? apiKey = prefs.getString(kKey);
    String? apiUrl = prefs.getString(uKey);
    String? provider = prefs.getString(pKey);

    // 迁移检查
    if (model == null) {
      final String? username = await UserSessionStorage.getCurrentUsername();
      if (username != null && username.isNotEmpty) {
        final markerKey = "${_chatModelKey}_${username}_migrated";
        if (!(prefs.getBool(markerKey) ?? false)) {
          model = prefs.getString(_chatModelKey);
          apiKey = prefs.getString(_chatApiKeyKey);
          apiUrl = prefs.getString(_chatApiUrlKey);
          if (model != null) {
            await prefs.setString(mKey, model);
            if (apiKey != null) await prefs.setString(kKey, apiKey);
            if (apiUrl != null) await prefs.setString(uKey, apiUrl);
            await prefs.setBool(markerKey, true);
          }
        }
      }
    }

    if (model == null || model.isEmpty) return null;
    return {
      'model': model,
      'apiKey': apiKey ?? '',
      'apiUrl':
          apiUrl ?? 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      'provider': provider ?? '',
    };
  }

  static Future<void> saveChatConfig({
    required String model,
    required String apiKey,
    String? apiUrl,
    String? provider,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mKey = await _getScopedKey(_chatModelKey);
    final kKey = await _getScopedKey(_chatApiKeyKey);
    final uKey = await _getScopedKey(_chatApiUrlKey);
    final pKey = await _getScopedKey(_chatProviderKey);

    if (model.isEmpty) {
      await prefs.remove(mKey);
      await prefs.remove(kKey);
      await prefs.remove(uKey);
      await prefs.remove(pKey);
    } else {
      await prefs.setString(mKey, model);
      if (apiKey.isNotEmpty) {
        await prefs.setString(kKey, apiKey);
      }
      if (apiUrl != null && apiUrl.isNotEmpty) {
        await prefs.setString(uKey, apiUrl);
      }
      if (provider != null && provider.isNotEmpty) {
        await prefs.setString(pKey, provider);
      }
    }
  }

  static Future<void> clearChatConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final mKey = await _getScopedKey(_chatModelKey);
    final kKey = await _getScopedKey(_chatApiKeyKey);
    final uKey = await _getScopedKey(_chatApiUrlKey);
    final pKey = await _getScopedKey(_chatProviderKey);
    await prefs.remove(mKey);
    await prefs.remove(kKey);
    await prefs.remove(uKey);
    await prefs.remove(pKey);
  }

  static Future<bool> isDeepThinkingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_deepThinkingKey);
    return prefs.getBool(scopedKey) ?? false;
  }

  static Future<void> setDeepThinkingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_deepThinkingKey);
    await prefs.setBool(scopedKey, enabled);
  }
}
