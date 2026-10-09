import '../models/chat_message.dart';

abstract final class AiChatHistoryWindow {
  static ({ChatMessage firstUserMessage, List<ChatMessage> recentMessages})
  selectRecentMessages(
    List<ChatMessage> messages, {
    required int maxContextMessages,
  }) {
    if (messages.length <= maxContextMessages) {
      throw ArgumentError.value(
        messages.length,
        'messages.length',
        'Must exceed maxContextMessages',
      );
    }
    if (maxContextMessages < 3) {
      throw ArgumentError.value(
        maxContextMessages,
        'maxContextMessages',
        'Must leave room for the first message and a summary',
      );
    }

    final firstUserMessage = messages.firstWhere(
      (message) => message.role == ChatRole.user,
      orElse: () => messages.first,
    );
    final recentCount = maxContextMessages - 2;
    final startIndex = messages.length - recentCount;
    final recentMessages = messages
        .sublist(startIndex > 0 ? startIndex : 0)
        .where((message) => message.id != firstUserMessage.id)
        .toList(growable: false);

    return (firstUserMessage: firstUserMessage, recentMessages: recentMessages);
  }
}
