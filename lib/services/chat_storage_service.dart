import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/ai_context_mode.dart';
import '../models/chat_message.dart';
import 'ai_action_parser.dart';
import 'legacy_ai_prompt_sanitizer.dart';
import 'storage/user_session_storage.dart';
import 'storage/storage_key_scope.dart';
import 'secure_storage_service.dart';

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
  }) : id = id ?? const Uuid().v4(),
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
  static Future<void> _sessionCreationQueue = Future<void>.value();

  static const String _sessionsKey = 'chat_sessions';
  static const String _activeSessionKey = 'chat_active_session';
  static const String _customPromptKey = 'chat_custom_prompt';
  static const String _promptProtocolVersionKey =
      'chat_prompt_protocol_version';
  static const int promptProtocolVersion = 2;
  static const String _promptEnabledKey = 'chat_prompt_enabled';
  static const String _chatModelKey = 'chat_model';
  static const String _chatApiKeyKey = 'chat_api_key';
  static const String _chatApiUrlKey = 'chat_api_url';
  static const String _chatProviderKey = 'chat_provider';
  static const String _deepThinkingKey = 'chat_deep_thinking';
  static const String _smartContextKey = 'chat_smart_context';
  static const String _contextModeKey = 'chat_context_mode';
  static const String _showContextPreviewKey = 'chat_show_context_preview';
  static const String _injectMoreContextKey = 'chat_inject_more_context';

  // 🚀 私有助手：获取隔离的存储 Key
  static Future<String> _getScopedKey(String baseKey) async {
    final username = await UserSessionStorage.getCurrentUsername();
    return StorageKeyScope.scoped(baseKey, username);
  }

  static const String _defaultPrompt =
      '''你是一个智能效率助手。结合用户本轮请求和提供的上下文，用简洁的中文回答，并给出具体、可执行的建议。

【当前时间】
{now}

【待办上下文】
{todos}

【回复要求】
- 使用简洁、清楚的中文和Markdown；建议应具体可执行。
- 日期、事项类型和操作范围以本轮请求及系统提供的数据为准；缺少关键信息时先追问。
- 不要声称尚未完成或仍待确认的操作已经保存。''';

  static const String _currentPromptProtocol = '''
【CDT 当前聊天协议 v2 | CDT_CHAT_PROTOCOL_V2】
- 普通待办只能使用create_todo，时间字段使用timeMode=unscheduled/dateOnly/deadline和dueDate；不要把普通待办表示成时间区间。
- 把已有待办安排到用户可调整的执行时段时，必须使用create_plan_block并携带上下文中的真实todoId；不得复制创建同名待办。
- 输出结构化动作时必须使用CDT Actions v2信封，并为每个对象提供action字段。
- 不得输出任何旧版动作标记、旧版规划动作名或缺少action字段的todos/updates对象。
- 周期性事项类型不明确时先询问用户选择习惯或循环待办，不生成创建动作。''';

  static String get defaultPrompt => '$_defaultPrompt\n$_currentPromptProtocol';

  /// Removes the appended text protocol when a provider uses native tools.
  /// Older user prompts may still contain the v2 section after migration.
  static String removeCurrentTextProtocol(String prompt) {
    return prompt
        .replaceFirst(
          RegExp(
            r'(?:^|\n)【CDT 当前聊天协议 v\d+ \| CDT_CHAT_PROTOCOL_V\d+】[\s\S]*$',
          ),
          '',
        )
        .trim();
  }

  static String ensureCurrentPromptProtocol(String prompt) {
    final value = prompt.trim();
    if (value.isEmpty) return defaultPrompt;
    final sanitized = LegacyAiPromptSanitizer.sanitize(
      prompt,
      fallback: _defaultPrompt,
    );
    if (sanitized.contains('CDT_CHAT_PROTOCOL_V2')) return sanitized;
    return '$sanitized\n$_currentPromptProtocol';
  }

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
    return _withSessionCreationLock(() => _createSession(title: title));
  }

  static Future<ChatSession> _createSession({String? title}) async {
    final sessions = await loadSessions();
    final newSession = ChatSession(title: title ?? '新对话');
    sessions.insert(0, newSession);
    await saveSessions(sessions);
    await setActiveSessionId(newSession.id);
    return newSession;
  }

  /// Opens the assistant without history, reusing only the last empty session.
  static Future<ChatSession> openEmptySession() async {
    return _withSessionCreationLock(() async {
      final sessions = await loadSessions();
      final activeId = await getActiveSessionId();
      final previousSession = sessions
          .where((session) => session.id == activeId)
          .firstOrNull;
      if (previousSession != null &&
          (await loadHistory(previousSession.id)).isEmpty) {
        return previousSession;
      }
      return _createSession();
    });
  }

  static Future<T> _withSessionCreationLock<T>(
    Future<T> Function() action,
  ) async {
    final previous = _sessionCreationQueue;
    final release = Completer<void>();
    _sessionCreationQueue = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
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

  static Future<void> updateSessionTitle(String sessionId, String title) async {
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
      final history = jsonList
          .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
          .toList();
      var changed = false;
      final migratedHistory = history.map((message) {
        if (message.role != ChatRole.assistant) return message;
        final cleanedContent = AiActionParser.cleanActionContent(
          message.content,
        );
        if (cleanedContent == message.content) return message;
        changed = true;
        return message.copyWith(content: cleanedContent);
      }).toList();
      if (changed) await saveHistory(migratedHistory, sid);
      return migratedHistory;
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

  static Future<void> addMessage(
    ChatMessage message, {
    String? sessionId,
  }) async {
    final sid = sessionId ?? await getActiveSessionId();
    if (sid == null) return;
    final history = await loadHistory(sid);
    history.add(message);
    await saveHistory(history, sid);
    if (history.length == 2 && message.role == ChatRole.assistant) {
      final sessions = await loadSessions();
      final session = sessions
          .where((session) => session.id == sid)
          .firstOrNull;
      if (session != null && session.title == '新对话') {
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

  static Future<bool> updateMessage(
    ChatMessage message, {
    required String sessionId,
  }) async {
    final history = await loadHistory(sessionId);
    final index = history.indexWhere((item) => item.id == message.id);
    if (index == -1) return false;
    history[index] = message;
    await saveHistory(history, sessionId);
    return true;
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
    final stored = prefs.getString(scopedKey);
    if (stored == null || stored.trim().isEmpty) return defaultPrompt;
    final migrated = ensureCurrentPromptProtocol(stored);
    final versionKey = await _getScopedKey(_promptProtocolVersionKey);
    if (migrated != stored ||
        prefs.getInt(versionKey) != promptProtocolVersion) {
      await prefs.setString(scopedKey, migrated);
      await prefs.setInt(versionKey, promptProtocolVersion);
    }
    return migrated;
  }

  static Future<void> saveCustomPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_customPromptKey);
    if (prompt.trim().isEmpty) {
      await prefs.remove(scopedKey);
      await prefs.remove(await _getScopedKey(_promptProtocolVersionKey));
    } else {
      await prefs.setString(scopedKey, ensureCurrentPromptProtocol(prompt));
      await prefs.setInt(
        await _getScopedKey(_promptProtocolVersionKey),
        promptProtocolVersion,
      );
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
    await prefs.remove(await _getScopedKey(_promptProtocolVersionKey));
  }

  static Future<Map<String, String>?> getChatConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final mKey = await _getScopedKey(_chatModelKey);
    final kKey = await _getScopedKey(_chatApiKeyKey);
    final uKey = await _getScopedKey(_chatApiUrlKey);
    final pKey = await _getScopedKey(_chatProviderKey);

    String? model = prefs.getString(mKey);
    String? legacyApiKey = prefs.getString(kKey);
    String? apiKey = await SecureStorageService.read(kKey);
    String? apiUrl = prefs.getString(uKey);
    String? provider = prefs.getString(pKey);

    // 迁移检查
    if (model == null) {
      final String? username = await UserSessionStorage.getCurrentUsername();
      if (username != null && username.isNotEmpty) {
        final markerKey = "${_chatModelKey}_${username}_migrated";
        if (!(prefs.getBool(markerKey) ?? false)) {
          model = prefs.getString(_chatModelKey);
          legacyApiKey = prefs.getString(_chatApiKeyKey);
          apiUrl = prefs.getString(_chatApiUrlKey);
          if (model != null) {
            await prefs.setString(mKey, model);
            if (apiUrl != null) await prefs.setString(uKey, apiUrl);
            await prefs.setBool(markerKey, true);
          }
        }
      }
    }

    if (legacyApiKey != null && legacyApiKey.isNotEmpty) {
      final migrated = apiKey != null && apiKey.isNotEmpty
          ? true
          : await SecureStorageService.write(kKey, legacyApiKey);
      if (apiKey == null || apiKey.isEmpty) apiKey = legacyApiKey;
      if (migrated) {
        await prefs.remove(kKey);
        await prefs.remove(_chatApiKeyKey);
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
      await SecureStorageService.delete(kKey);
      await prefs.remove(kKey);
      await prefs.remove(uKey);
      await prefs.remove(pKey);
    } else {
      await prefs.setString(mKey, model);
      if (apiKey.isNotEmpty) {
        await SecureStorageService.write(kKey, apiKey);
        await prefs.remove(kKey);
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
    await SecureStorageService.delete(kKey);
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

  static Future<bool> isSmartContextEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_smartContextKey);
    return prefs.getBool(scopedKey) ?? true;
  }

  static Future<AiContextMode> getContextMode() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_contextModeKey);
    return AiContextMode.fromStorage(prefs.getString(scopedKey));
  }

  static Future<void> setContextMode(AiContextMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_contextModeKey);
    await prefs.setString(scopedKey, mode.name);
  }

  static Future<void> setSmartContextEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_smartContextKey);
    await prefs.setBool(scopedKey, enabled);
  }

  static Future<bool> shouldShowContextPreview() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_showContextPreviewKey);
    return prefs.getBool(scopedKey) ?? false;
  }

  static Future<void> setShowContextPreview(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_showContextPreviewKey);
    await prefs.setBool(scopedKey, enabled);
  }

  static Future<bool> shouldInjectMoreContext() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_injectMoreContextKey);
    return prefs.getBool(scopedKey) ?? false;
  }

  static Future<void> setInjectMoreContext(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_injectMoreContextKey);
    await prefs.setBool(scopedKey, enabled);
  }
}
