import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'ai_todo_action.dart';
import '../features/finance/models/finance_models.dart';

enum ChatRole { user, assistant }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final String rawContent;
  final String reasoningContent;
  final String smartContext;
  final DateTime timestamp;
  final List<AiTodoAction>? todoActions;
  final List<FinanceEntryDraft>? financeDrafts;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    this.rawContent = '',
    this.reasoningContent = '',
    this.smartContext = '',
    DateTime? timestamp,
    this.todoActions,
    this.financeDrafts,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'rawContent': rawContent,
        'reasoningContent': reasoningContent,
        'smartContext': smartContext,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'todoActions': todoActions?.map((e) => e.toJson()).toList(),
        'financeDrafts': financeDrafts?.map((e) => e.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? const Uuid().v4(),
      role: json['role'] == 'assistant' ? ChatRole.assistant : ChatRole.user,
      content: json['content'] as String,
      rawContent: json['rawContent'] as String? ?? '',
      reasoningContent: json['reasoningContent'] as String? ?? '',
      smartContext: json['smartContext'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ).toLocal(),
      todoActions: (json['todoActions'] as List?)
          ?.whereType<Map>()
          .map((e) => AiTodoAction.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      financeDrafts: (json['financeDrafts'] as List?)
          ?.whereType<Map>()
          .map((e) => FinanceEntryDraft.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  String toLLMMessage() {
    final contextDrafts = financeDrafts
        ?.where((draft) => !draft.isIgnored)
        .map(
          (draft) => {
            'type': draft.type.name,
            'amount': draft.amountMinor / 100,
            'category': draft.categoryName,
            'merchant': draft.merchant,
            'date': draft.transactionDate,
            'paymentMethod': draft.paymentMethodName,
            'note': draft.note,
            'isAdded': draft.isAdded,
          },
        )
        .toList();
    if (contextDrafts != null && contextDrafts.isNotEmpty) {
      return '$content\n\n[FINANCE_DRAFT_CONTEXT]\n'
          '${jsonEncode(contextDrafts)}'
          '\n[/FINANCE_DRAFT_CONTEXT]';
    }
    return content;
  }
}
