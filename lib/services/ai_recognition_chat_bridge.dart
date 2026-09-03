import 'package:flutter/foundation.dart';

import '../features/finance/models/finance_models.dart';
import '../models/chat_message.dart';
import 'chat_storage_service.dart';

class AiRecognitionHandle {
  final String sessionId;
  final String messageId;

  const AiRecognitionHandle({
    required this.sessionId,
    required this.messageId,
  });
}

/// Keeps the standalone todo-recognition flows visible in the AI assistant.
///
/// Recognition is still executed by its original caller. This bridge only
/// mirrors the lifecycle into the local chat history, so a background import
/// can be opened from the home page without coupling the UI to the recognizer.
class AiRecognitionChatBridge {
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<AiRecognitionHandle> startText(
    String text, {
    String recognizer = '文本识别',
  }) {
    return _start(
      source: 'text',
      inputText: text,
      recognizer: recognizer,
    );
  }

  static Future<AiRecognitionHandle> startImage(
    String imagePath, {
    String? inputText,
    String recognizer = '图片识别',
  }) {
    return _start(
      source: 'image',
      imagePath: imagePath,
      inputText: inputText,
      recognizer: recognizer,
    );
  }

  static Future<AiRecognitionHandle> _start({
    required String source,
    String? inputText,
    String? imagePath,
    required String recognizer,
  }) async {
    final session = await _ensureActiveSession();
    final userMessage = ChatMessage(
      role: ChatRole.user,
      kind: ChatMessageKind.recognition,
      content: source == 'image'
          ? (inputText?.trim().isNotEmpty == true
              ? inputText!.trim()
              : '请识别这张图片中的待办事项。')
          : '请从下面的文本中识别待办事项：\n${inputText?.trim() ?? ''}',
      attachment: imagePath == null
          ? null
          : ChatImageAttachment(
              path: imagePath,
              name: _imageName(imagePath),
              mimeType: _imageMimeType(imagePath),
            ),
    );
    final now = DateTime.now();
    final statusMessage = ChatMessage(
      role: ChatRole.assistant,
      kind: ChatMessageKind.recognition,
      content: 'AI识别中…',
      recognition: ChatRecognitionInfo(
        source: source,
        status: ChatRecognitionStatus.processing,
        recognizer: recognizer,
        inputText: inputText,
        imagePath: imagePath,
        startedAt: now,
      ),
    );
    await ChatStorageService.addMessage(userMessage, sessionId: session.id);
    await ChatStorageService.addMessage(statusMessage, sessionId: session.id);
    _notifyChanged();
    return AiRecognitionHandle(
      sessionId: session.id,
      messageId: statusMessage.id,
    );
  }

  static Future<void> markProcessing(AiRecognitionHandle handle) async {
    try {
      final existing = await _findMessage(handle);
      final info = existing?.recognition;
      if (existing == null || info == null) return;
      await ChatStorageService.updateMessage(
        existing.copyWith(
          content: 'AI识别中…',
          clearUsageSummary: true,
          clearFinanceDrafts: true,
          recognition: info.copyWith(
            status: ChatRecognitionStatus.processing,
            todoResults: const [],
            suggestions: const [],
            clearCompletedAt: true,
            clearError: true,
          ),
        ),
        sessionId: handle.sessionId,
      );
      _notifyChanged();
    } catch (_) {
      // Chat mirroring is best effort and must not interrupt recognition.
    }
  }

  static Future<void> complete(
    AiRecognitionHandle handle, {
    required List<Map<String, dynamic>> todoResults,
    List<FinanceEntryDraft> financeDrafts = const [],
    ChatUsageSummary? usageSummary,
  }) async {
    try {
      final existing = await _findMessage(handle);
      final info = existing?.recognition;
      if (existing == null || info == null) return;
      final total = todoResults.length + financeDrafts.length;
      final content = total == 0
          ? '识别完成，未发现可添加的事项。'
          : '识别完成：发现 ${todoResults.length} 个待办'
              '${financeDrafts.isEmpty ? '' : '、${financeDrafts.length} 笔账单'}，'
              '请返回确认卡核对后保存。';
      final suggestions = total == 0
          ? const ['换个更清晰的内容重试', '告诉我你想提取什么']
          : const ['检查时间与提醒', '继续分析这些事项', '返回确认卡保存'];
      await ChatStorageService.updateMessage(
        existing.copyWith(
          content: content,
          financeDrafts: financeDrafts.isEmpty ? null : financeDrafts,
          usageSummary: usageSummary,
          clearUsageSummary: usageSummary == null,
          clearFinanceDrafts: financeDrafts.isEmpty,
          recognition: info.copyWith(
            status: ChatRecognitionStatus.success,
            todoResults: todoResults,
            suggestions: suggestions,
            completedAt: DateTime.now(),
            clearError: true,
          ),
        ),
        sessionId: handle.sessionId,
      );
      _notifyChanged();
    } catch (_) {
      // Chat mirroring is best effort and must not interrupt recognition.
    }
  }

  static Future<void> fail(
    AiRecognitionHandle handle,
    Object error,
  ) async {
    try {
      final existing = await _findMessage(handle);
      final info = existing?.recognition;
      if (existing == null || info == null) return;
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      await ChatStorageService.updateMessage(
        existing.copyWith(
          content: '识别失败：${message.isEmpty ? '未知错误' : message}',
          clearUsageSummary: true,
          clearFinanceDrafts: true,
          recognition: info.copyWith(
            status: ChatRecognitionStatus.failed,
            todoResults: const [],
            suggestions: const ['重试识别', '换个文件或直接描述内容'],
            error: message.isEmpty ? '未知错误' : message,
            completedAt: DateTime.now(),
          ),
        ),
        sessionId: handle.sessionId,
      );
      _notifyChanged();
    } catch (_) {
      // Chat mirroring is best effort and must not interrupt recognition.
    }
  }

  static AiRecognitionHandle? handleFromPending(
    Map<String, dynamic>? pending,
  ) {
    if (pending == null) return null;
    final sessionId = pending['recognitionChatSessionId']?.toString().trim();
    final messageId = pending['recognitionChatMessageId']?.toString().trim();
    if (sessionId == null ||
        sessionId.isEmpty ||
        messageId == null ||
        messageId.isEmpty) {
      return null;
    }
    return AiRecognitionHandle(sessionId: sessionId, messageId: messageId);
  }

  static Future<ChatMessage?> _findMessage(AiRecognitionHandle handle) async {
    final history = await ChatStorageService.loadHistory(handle.sessionId);
    for (final message in history) {
      if (message.id == handle.messageId) return message;
    }
    return null;
  }

  static Future<ChatSession> _ensureActiveSession() async {
    final sessions = await ChatStorageService.loadSessions();
    final activeId = await ChatStorageService.getActiveSessionId();
    if (activeId != null) {
      for (final session in sessions) {
        if (session.id == activeId) return session;
      }
    }
    if (sessions.isNotEmpty) {
      await ChatStorageService.setActiveSessionId(sessions.first.id);
      return sessions.first;
    }
    return ChatStorageService.createSession(title: 'AI识别');
  }

  static void _notifyChanged() {
    changes.value++;
  }

  static String _imageName(String path) {
    final normalized = path.split('/').last;
    return normalized.isEmpty ? '图片' : normalized;
  }

  static String _imageMimeType(String path) {
    switch (path.split('?').first.split('.').last.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }
}
