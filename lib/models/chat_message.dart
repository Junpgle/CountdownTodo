import 'package:uuid/uuid.dart';

enum ChatRole { user, assistant }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final String reasoningContent;
  final DateTime timestamp;
  final List<Map<String, dynamic>>? todoActions;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    this.reasoningContent = '',
    DateTime? timestamp,
    this.todoActions,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'reasoningContent': reasoningContent,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'todoActions': todoActions,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? const Uuid().v4(),
      role: json['role'] == 'assistant' ? ChatRole.assistant : ChatRole.user,
      content: json['content'] as String,
      reasoningContent: json['reasoningContent'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ).toLocal(),
      todoActions: (json['todoActions'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  String toLLMMessage() {
    return content;
  }
}
