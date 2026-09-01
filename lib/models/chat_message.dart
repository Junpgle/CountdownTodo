import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'ai_todo_action.dart';
import '../features/finance/models/finance_ai_action.dart';
import '../features/finance/models/finance_models.dart';

enum ChatRole { user, assistant }

enum ChatMessageKind { conversation, recognition }

enum ChatRecognitionStatus { processing, success, failed }

enum ChatAttachmentKind { image, audio, video, document }

class ChatImageAttachment {
  final String path;
  final String name;
  final String mimeType;
  final int? sizeBytes;
  final ChatAttachmentKind kind;

  /// Bytes are kept only for the current in-memory session. They are
  /// deliberately excluded from chat history JSON so a local image cannot
  /// silently turn SharedPreferences into a binary store.
  final Uint8List? bytes;

  ChatImageAttachment({
    required this.path,
    required this.name,
    required this.mimeType,
    this.sizeBytes,
    this.bytes,
    ChatAttachmentKind? kind,
  }) : kind = kind ?? _attachmentKindFromMimeType(mimeType);

  String get typeLabel => switch (kind) {
        ChatAttachmentKind.image => '图片',
        ChatAttachmentKind.audio => '音频',
        ChatAttachmentKind.video => '视频',
        ChatAttachmentKind.document => '文件',
      };

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'kind': kind.name,
      };

  factory ChatImageAttachment.fromJson(Map<String, dynamic> json) {
    return ChatImageAttachment(
      path: json['path']?.toString() ?? '',
      name: json['name']?.toString() ?? '图片',
      mimeType: json['mimeType']?.toString() ?? 'image/jpeg',
      sizeBytes: _readNullableInt(json['sizeBytes']),
      kind: ChatAttachmentKind.values.firstWhere(
        (value) => value.name == json['kind']?.toString(),
        orElse: () => _attachmentKindFromMimeType(
          json['mimeType']?.toString() ?? 'image/jpeg',
        ),
      ),
    );
  }
}

class ChatUsageSummary {
  final String provider;
  final String model;
  final int calls;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int cachedPromptTokens;
  final int imageTokens;
  final int audioTokens;
  final int videoTokens;
  final int reasoningTokens;
  final int audioSeconds;
  final int imageCount;
  final int? costMicros;
  final int unpricedCalls;

  const ChatUsageSummary({
    required this.provider,
    required this.model,
    this.calls = 1,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.cachedPromptTokens = 0,
    this.imageTokens = 0,
    this.audioTokens = 0,
    this.videoTokens = 0,
    this.reasoningTokens = 0,
    this.audioSeconds = 0,
    this.imageCount = 0,
    this.costMicros,
    this.unpricedCalls = 0,
  });

  bool get isFullyPriced => costMicros != null && unpricedCalls == 0;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        'calls': calls,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'totalTokens': totalTokens,
        'cachedPromptTokens': cachedPromptTokens,
        'imageTokens': imageTokens,
        'audioTokens': audioTokens,
        'videoTokens': videoTokens,
        'reasoningTokens': reasoningTokens,
        'audioSeconds': audioSeconds,
        'imageCount': imageCount,
        'costMicros': costMicros,
        'unpricedCalls': unpricedCalls,
      };

  factory ChatUsageSummary.fromJson(Map<String, dynamic> json) {
    return ChatUsageSummary(
      provider: json['provider']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      calls: _readNullableInt(json['calls']) ?? 1,
      promptTokens: _readNullableInt(json['promptTokens']) ?? 0,
      completionTokens: _readNullableInt(json['completionTokens']) ?? 0,
      totalTokens: _readNullableInt(json['totalTokens']) ?? 0,
      cachedPromptTokens: _readNullableInt(json['cachedPromptTokens']) ?? 0,
      imageTokens: _readNullableInt(json['imageTokens']) ?? 0,
      audioTokens: _readNullableInt(json['audioTokens']) ?? 0,
      videoTokens: _readNullableInt(json['videoTokens']) ?? 0,
      reasoningTokens: _readNullableInt(json['reasoningTokens']) ?? 0,
      audioSeconds: _readNullableInt(json['audioSeconds']) ?? 0,
      imageCount: _readNullableInt(json['imageCount']) ?? 0,
      costMicros: _readNullableInt(json['costMicros']),
      unpricedCalls: _readNullableInt(json['unpricedCalls']) ?? 0,
    );
  }

  static ChatUsageSummary? combine(Iterable<ChatUsageSummary> values) {
    final items = values.toList();
    if (items.isEmpty) return null;
    final providers = items.map((item) => item.provider).toSet();
    final models = items.map((item) => item.model).toSet();
    final priced = items.where((item) => item.costMicros != null).toList();
    return ChatUsageSummary(
      provider: providers.length == 1 ? providers.single : '多服务商',
      model: models.length == 1 ? models.single : '多模型',
      calls: items.fold(0, (sum, item) => sum + item.calls),
      promptTokens: items.fold(0, (sum, item) => sum + item.promptTokens),
      completionTokens:
          items.fold(0, (sum, item) => sum + item.completionTokens),
      totalTokens: items.fold(0, (sum, item) => sum + item.totalTokens),
      cachedPromptTokens:
          items.fold(0, (sum, item) => sum + item.cachedPromptTokens),
      imageTokens: items.fold(0, (sum, item) => sum + item.imageTokens),
      audioTokens: items.fold(0, (sum, item) => sum + item.audioTokens),
      videoTokens: items.fold(0, (sum, item) => sum + item.videoTokens),
      reasoningTokens: items.fold(0, (sum, item) => sum + item.reasoningTokens),
      audioSeconds: items.fold(0, (sum, item) => sum + item.audioSeconds),
      imageCount: items.fold(0, (sum, item) => sum + item.imageCount),
      costMicros: priced.isEmpty
          ? null
          : priced
              .map((item) => item.costMicros ?? 0)
              .fold<int>(0, (sum, cost) => sum + cost),
      unpricedCalls: items.fold(0, (sum, item) => sum + item.unpricedCalls),
    );
  }
}

class ChatRecognitionInfo {
  final String source;
  final ChatRecognitionStatus status;
  final String recognizer;
  final String? inputText;
  final String? imagePath;
  final List<Map<String, dynamic>> todoResults;
  final List<String> suggestions;
  final String? error;
  final DateTime startedAt;
  final DateTime? completedAt;

  const ChatRecognitionInfo({
    required this.source,
    required this.status,
    this.recognizer = 'AI',
    this.inputText,
    this.imagePath,
    this.todoResults = const [],
    this.suggestions = const [],
    this.error,
    required this.startedAt,
    this.completedAt,
  });

  ChatRecognitionInfo copyWith({
    ChatRecognitionStatus? status,
    String? recognizer,
    String? inputText,
    String? imagePath,
    List<Map<String, dynamic>>? todoResults,
    List<String>? suggestions,
    String? error,
    DateTime? completedAt,
    bool clearError = false,
    bool clearCompletedAt = false,
  }) {
    return ChatRecognitionInfo(
      source: source,
      status: status ?? this.status,
      recognizer: recognizer ?? this.recognizer,
      inputText: inputText ?? this.inputText,
      imagePath: imagePath ?? this.imagePath,
      todoResults: todoResults ?? this.todoResults,
      suggestions: suggestions ?? this.suggestions,
      error: clearError ? null : error ?? this.error,
      startedAt: startedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'source': source,
        'status': status.name,
        'recognizer': recognizer,
        'inputText': inputText,
        'imagePath': imagePath,
        'todoResults': todoResults,
        'suggestions': suggestions,
        'error': error,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
      };

  factory ChatRecognitionInfo.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString();
    final status = ChatRecognitionStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => ChatRecognitionStatus.success,
    );
    final rawResults = json['todoResults'];
    return ChatRecognitionInfo(
      source: json['source']?.toString() ?? 'text',
      status: status,
      recognizer: json['recognizer']?.toString() ?? 'AI',
      inputText: json['inputText']?.toString(),
      imagePath: json['imagePath']?.toString(),
      todoResults: rawResults is List
          ? rawResults
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : const [],
      suggestions: (json['suggestions'] as List?)
              ?.map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList() ??
          const [],
      error: json['error']?.toString(),
      startedAt: _readDateTime(json['startedAt']) ?? DateTime.now(),
      completedAt: _readDateTime(json['completedAt']),
    );
  }
}

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final String rawContent;
  final String reasoningContent;
  final String smartContext;
  final DateTime timestamp;
  final ChatMessageKind kind;
  final ChatImageAttachment? attachment;
  final ChatRecognitionInfo? recognition;
  final ChatUsageSummary? usageSummary;
  final List<AiTodoAction>? todoActions;
  final List<FinanceEntryDraft>? financeDrafts;
  final List<FinanceAiAction>? financeActions;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    this.rawContent = '',
    this.reasoningContent = '',
    this.smartContext = '',
    DateTime? timestamp,
    this.kind = ChatMessageKind.conversation,
    this.attachment,
    this.recognition,
    this.usageSummary,
    this.todoActions,
    this.financeDrafts,
    this.financeActions,
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
        'kind': kind.name,
        'attachment': attachment?.toJson(),
        'recognition': recognition?.toJson(),
        'usageSummary': usageSummary?.toJson(),
        'todoActions': todoActions?.map((e) => e.toJson()).toList(),
        'financeDrafts': financeDrafts?.map((e) => e.toJson()).toList(),
        'financeActions': financeActions?.map((e) => e.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? const Uuid().v4(),
      role: json['role'] == 'assistant' ? ChatRole.assistant : ChatRole.user,
      content: json['content'] as String,
      rawContent: json['rawContent'] as String? ?? '',
      reasoningContent: json['reasoningContent'] as String? ?? '',
      smartContext: json['smartContext'] as String? ?? '',
      kind: ChatMessageKind.values.firstWhere(
        (value) => value.name == json['kind']?.toString(),
        orElse: () => ChatMessageKind.conversation,
      ),
      attachment: json['attachment'] is Map
          ? ChatImageAttachment.fromJson(
              Map<String, dynamic>.from(json['attachment'] as Map),
            )
          : null,
      recognition: json['recognition'] is Map
          ? ChatRecognitionInfo.fromJson(
              Map<String, dynamic>.from(json['recognition'] as Map),
            )
          : null,
      usageSummary: json['usageSummary'] is Map
          ? ChatUsageSummary.fromJson(
              Map<String, dynamic>.from(json['usageSummary'] as Map),
            )
          : null,
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
      financeActions: (json['financeActions'] as List?)
          ?.whereType<Map>()
          .map((e) => FinanceAiAction.fromJson(Map<String, dynamic>.from(e)))
          .where((action) => action.type != FinanceAiActionType.unknown)
          .toList(),
    );
  }

  ChatMessage copyWith({
    String? content,
    String? rawContent,
    String? reasoningContent,
    String? smartContext,
    ChatMessageKind? kind,
    ChatImageAttachment? attachment,
    ChatRecognitionInfo? recognition,
    ChatUsageSummary? usageSummary,
    bool clearUsageSummary = false,
    List<AiTodoAction>? todoActions,
    List<FinanceEntryDraft>? financeDrafts,
    bool clearFinanceDrafts = false,
    List<FinanceAiAction>? financeActions,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      rawContent: rawContent ?? this.rawContent,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      smartContext: smartContext ?? this.smartContext,
      timestamp: timestamp,
      kind: kind ?? this.kind,
      attachment: attachment ?? this.attachment,
      recognition: recognition ?? this.recognition,
      usageSummary:
          clearUsageSummary ? null : usageSummary ?? this.usageSummary,
      todoActions: todoActions ?? this.todoActions,
      financeDrafts:
          clearFinanceDrafts ? null : financeDrafts ?? this.financeDrafts,
      financeActions: financeActions ?? this.financeActions,
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
    final contextActions = financeActions
        ?.where((action) => !action.isIgnored)
        .map((action) => action.toJson())
        .toList();
    final sections = <String>[content];
    if (contextDrafts != null && contextDrafts.isNotEmpty) {
      sections.add(
        '[FINANCE_DRAFT_CONTEXT]\n${jsonEncode(contextDrafts)}\n'
        '[/FINANCE_DRAFT_CONTEXT]',
      );
    }
    if (contextActions != null && contextActions.isNotEmpty) {
      sections.add(
        '[FINANCE_ACTION_CONTEXT]\n${jsonEncode(contextActions)}\n'
        '[/FINANCE_ACTION_CONTEXT]',
      );
    }
    return sections.join('\n\n');
  }
}

int? _readNullableInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _readDateTime(Object? value) {
  final millis = _readNullableInt(value);
  return millis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
}

ChatAttachmentKind _attachmentKindFromMimeType(String mimeType) {
  final normalized = mimeType.toLowerCase();
  if (normalized.startsWith('audio/')) return ChatAttachmentKind.audio;
  if (normalized.startsWith('video/')) return ChatAttachmentKind.video;
  if (normalized.startsWith('image/')) return ChatAttachmentKind.image;
  return ChatAttachmentKind.document;
}
